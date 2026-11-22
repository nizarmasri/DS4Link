import Foundation
import IOBluetooth
import DS4LinkCore

/// Thin wrapper over IOBluetooth (classic Bluetooth, which is what PlayStation pads use).
/// Main thread only: IOBluetooth delivers its callbacks on the main run loop.
/// Every asynchronous call has its own timeout, because IOBluetooth callbacks sometimes never fire.
final class BluetoothDriver: NSObject, IOBluetoothDeviceInquiryDelegate, IOBluetoothDevicePairDelegate, IOBluetoothDeviceAsyncCallbacks {
    var onFound: ((DeviceSnapshot) -> Void)?
    var onInquiryFinished: ((_ error: Int32, _ aborted: Bool) -> Void)?
    /// Fires whenever any device connects or disconnects, as a nudge to re-read ground truth.
    var onConnectionEvent: (() -> Void)?

    private var inquiry: IOBluetoothDeviceInquiry?
    private var pairer: IOBluetoothDevicePair?
    private var pairCompletion: ((Int32) -> Void)?
    private var pairTimeout: DispatchWorkItem?
    private var connectDevice: IOBluetoothDevice?
    private var connectCompletion: ((Int32) -> Void)?
    private var connectTimeout: DispatchWorkItem?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    // MARK: Queries

    func snapshot(_ device: IOBluetoothDevice) -> DeviceSnapshot {
        DeviceSnapshot(
            address: Self.normalize(device.addressString),
            name: device.name,
            classOfDevice: device.classOfDevice,
            paired: device.isPaired(),
            connected: device.isConnected()
        )
    }

    func snapshot(address: String) -> DeviceSnapshot? {
        IOBluetoothDevice(addressString: address).map(snapshot)
    }

    func allPaired() -> [DeviceSnapshot] {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return devices.map(snapshot)
    }

    func pairedControllers() -> [DeviceSnapshot] {
        allPaired().filter { ControllerMatcher.isGameController(name: $0.name, classOfDevice: $0.classOfDevice) }
    }

    static func normalize(_ address: String?) -> String {
        (address ?? "").lowercased().replacingOccurrences(of: ":", with: "-")
    }

    // MARK: Connection notifications

    func startWatchingConnections() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = Self.normalize(device.addressString)
        Log.info("bt connected: \(address) \(device.name ?? "?")")
        if disconnectNotifications[address] == nil {
            disconnectNotifications[address] = device.register(
                forDisconnectNotification: self,
                selector: #selector(deviceDisconnected(_:device:))
            )
        }
        onConnectionEvent?()
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = Self.normalize(device.addressString)
        Log.info("bt disconnected: \(address) \(device.name ?? "?")")
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = nil
        onConnectionEvent?()
    }

    // MARK: Inquiry (finding a controller that is in pairing mode)

    /// Starts scanning. Since macOS 12 an inquiry ignores `inquiryLength` and runs until it is
    /// stopped, and "device found" callbacks are not dependable, so callers poll `foundDevices()`
    /// while it runs and end each cycle themselves with `finishInquiry()` or `stopInquiry()`.
    /// A fresh inquiry object is used per cycle: a reused one can carry stale state.
    @discardableResult
    func startInquiry(resolveNames: Bool) -> Int32 {
        dropInquiry()
        guard let next = IOBluetoothDeviceInquiry(delegate: self) else { return IOCode.error }
        next.inquiryLength = 10
        next.updateNewDeviceNames = resolveNames
        inquiry = next
        let result = next.start()
        if result != IOCode.success {
            Log.warn("inquiry start failed: \(IOCode.hex(result))")
            dropInquiry()
        }
        return result
    }

    var isInquiring: Bool { inquiry != nil }

    /// Everything the running inquiry has seen so far.
    func foundDevices() -> [DeviceSnapshot] {
        ((inquiry?.foundDevices() as? [IOBluetoothDevice]) ?? []).map(snapshot)
    }

    /// Asks the inquiry to wrap up. macOS then resolves the names of what it found and reports
    /// completion through `onInquiryFinished`; the caller must not rely on that ever arriving.
    func finishInquiry() {
        inquiry?.stop()
    }

    /// Ends the inquiry immediately and silently.
    func stopInquiry() {
        dropInquiry()
    }

    private func dropInquiry() {
        inquiry?.delegate = nil
        inquiry?.stop()
        inquiry = nil
    }

    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard sender === inquiry, let device else { return }
        onFound?(snapshot(device))
    }

    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        guard sender === inquiry, let device else { return }
        onFound?(snapshot(device))
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        guard sender === inquiry else { return }
        let found = foundDevices()
        inquiry?.delegate = nil
        inquiry = nil
        found.forEach { onFound?($0) }
        onInquiryFinished?(error, aborted)
    }

    // MARK: Pairing

    func pair(address: String, timeout: TimeInterval = 30, completion: @escaping (Int32) -> Void) {
        cancelPairing()
        guard let device = IOBluetoothDevice(addressString: address),
              let next = IOBluetoothDevicePair(device: device) else {
            completion(IOCode.noDevice)
            return
        }
        next.delegate = self
        pairer = next
        pairCompletion = completion

        let result = next.start()
        Log.info("pair start \(address): \(IOCode.hex(result))")
        guard result == IOCode.success else {
            finishPairing(result)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            Log.warn("pair \(address): no answer after \(Int(timeout))s")
            self?.finishPairing(IOCode.timeout)
        }
        pairTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func cancelPairing() {
        pairTimeout?.cancel()
        pairTimeout = nil
        pairCompletion = nil
        pairer?.delegate = nil
        pairer?.stop()
        pairer = nil
    }

    private func finishPairing(_ code: Int32) {
        pairTimeout?.cancel()
        pairTimeout = nil
        let completion = pairCompletion
        pairCompletion = nil
        if code != IOCode.success { pairer?.stop() }
        pairer?.delegate = nil
        pairer = nil
        completion?(code)
    }

    func devicePairingStarted(_ sender: Any!) {
        Log.info("pair: started")
    }

    func devicePairingConnecting(_ sender: Any!) {
        Log.info("pair: connecting")
    }

    func devicePairingPINCodeRequest(_ sender: Any!) {
        // PlayStation pads do not ask for a PIN; clones that do accept 0000.
        Log.info("pair: PIN requested, answering 0000")
        guard let pair = sender as? IOBluetoothDevicePair else { return }
        var pin = BluetoothPINCode()
        let digits = Array("0000".utf8)
        withUnsafeMutableBytes(of: &pin) { buffer in
            for (index, digit) in digits.enumerated() where index < buffer.count {
                buffer[index] = digit
            }
        }
        pair.replyPINCode(digits.count, pinCode: &pin)
    }

    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        // "Just works" pairing: a pad has no display to compare numbers on, so accept.
        Log.info("pair: confirmation requested, accepting")
        (sender as? IOBluetoothDevicePair)?.replyUserConfirmation(true)
    }

    func devicePairingUserPasskeyNotification(_ sender: Any!, passkey: BluetoothPasskey) {
        Log.info("pair: passkey notification \(passkey)")
    }

    func deviceSimplePairingComplete(_ sender: Any!, status: BluetoothHCIEventStatus) {
        Log.info("pair: simple pairing complete, status \(status)")
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        guard let finished = sender as? IOBluetoothDevicePair, finished === pairer else { return }
        Log.info("pair: finished \(IOCode.hex(error))")
        finishPairing(error)
    }

    // MARK: Connecting

    func connect(address: String, timeout: TimeInterval = 15, completion: @escaping (Int32) -> Void) {
        cancelConnect()
        guard let device = IOBluetoothDevice(addressString: address) else {
            completion(IOCode.noDevice)
            return
        }
        if device.isConnected() {
            completion(IOCode.success)
            return
        }
        connectDevice = device
        connectCompletion = completion
        let result = device.openConnection(self)
        Log.info("connect start \(address): \(IOCode.hex(result))")
        guard result == IOCode.success else {
            finishConnect(result)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            Log.warn("connect \(address): no answer after \(Int(timeout))s")
            self?.finishConnect(IOCode.timeout)
        }
        connectTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func cancelConnect() {
        connectTimeout?.cancel()
        connectTimeout = nil
        connectCompletion = nil
        connectDevice = nil
    }

    private func finishConnect(_ code: Int32) {
        connectTimeout?.cancel()
        connectTimeout = nil
        let completion = connectCompletion
        connectCompletion = nil
        connectDevice = nil
        completion?(code)
    }

    func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard let device, device === connectDevice
            || Self.normalize(device.addressString) == Self.normalize(connectDevice?.addressString) else { return }
        Log.info("connect: complete \(IOCode.hex(status))")
        finishConnect(status)
    }

    func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}

    func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}

    // MARK: Disconnect / forget

    /// Closing the link is also how a DualShock is switched off: it powers down when the host hangs up.
    @discardableResult
    func disconnect(address: String) -> Int32 {
        guard let device = IOBluetoothDevice(addressString: address) else { return IOCode.noDevice }
        guard device.isConnected() else { return IOCode.success }
        let result = device.closeConnection()
        Log.info("disconnect \(address): \(IOCode.hex(result))")
        return result
    }

    /// Removes the pairing record. IOBluetooth has no public call for this; `remove` is the
    /// selector System Settings itself uses, so it is looked up at runtime and skipped if absent.
    @discardableResult
    func forget(address: String) -> Bool {
        guard let device = IOBluetoothDevice(addressString: address) else { return false }
        if device.isConnected() { device.closeConnection() }
        let selector = Selector(("remove"))
        guard device.responds(to: selector) else {
            Log.warn("forget \(address): this macOS has no remove selector")
            return false
        }
        device.perform(selector)
        Log.info("forget \(address): removed")
        return true
    }

    // MARK: Power

    /// Turns the Bluetooth radio on. There is no public API for this, so the symbol is resolved
    /// at runtime; when it is missing the caller falls back to opening Bluetooth settings.
    static func powerOn() -> Bool {
        typealias SetPower = @convention(c) (Int32) -> Int32
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW),
              let symbol = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") else {
            return false
        }
        _ = unsafeBitCast(symbol, to: SetPower.self)(1)
        return true
    }
}
