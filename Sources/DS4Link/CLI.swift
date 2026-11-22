import Foundation
import DS4LinkCore

/// Terminal access to the same driver and engine the window uses, for testing without clicking:
///   status            permission, radio power, every paired device, which ones count as controllers
///   scan [seconds]    one inquiry, listing everything that answers
///   auto [seconds]    the full engine: search, pair, connect, exactly as the app does
///   pair|connect|disconnect|forget <address>
enum CLI {
    static func run(_ args: [String]) -> Never {
        Log.echoToStderr = true
        let command = args.first ?? "status"
        let argument = args.dropFirst().first
        // Held statically: IOBluetooth does not retain its delegates, and a local would be
        // released after its last use, silently ending every callback.
        let driver = sharedDriver

        switch command {
        case "status":
            let authority = BluetoothAuthority()
            authority.start()
            spin(1.0)
            print("auth=\(authority.auth) power=\(authority.power)")
            guard authority.auth == .allowed else { finish(1) }
            for device in driver.allPaired() {
                let controller = ControllerMatcher.isGameController(name: device.name, classOfDevice: device.classOfDevice)
                print(line(device) + (controller ? "  <- controller" : ""))
            }
            print("controllers: \(driver.pairedControllers().count)")
            finish(0)

        case "scan":
            let seconds = Double(argument ?? "") ?? 8
            var seen: [String: String] = [:]
            var completed = false
            func report(_ device: DeviceSnapshot) {
                let text = line(device)
                guard seen[device.address] != text else { return }
                let controller = ControllerMatcher.isGameController(name: device.name, classOfDevice: device.classOfDevice)
                print((seen[device.address] == nil ? "found   " : "updated ") + text + (controller ? "  <- controller" : ""))
                seen[device.address] = text
            }
            driver.onFound = report
            driver.onInquiryFinished = { error, aborted in
                print("completion callback: \(IOCode.hex(error)) aborted=\(aborted)")
                completed = true
            }
            let result = driver.startInquiry(resolveNames: true)
            print("inquiry start: \(IOCode.hex(result))")
            guard result == IOCode.success else { finish(1) }
            let end = Date().addingTimeInterval(seconds)
            while Date() < end, !completed {
                spin(0.5)
                driver.foundDevices().forEach(report)
            }
            if !completed {
                driver.finishInquiry()
                spin(until: { completed }, limit: 6)
                driver.foundDevices().forEach(report)
            }
            print("devices seen: \(seen.count), completion callback arrived: \(completed)")
            driver.stopInquiry()
            finish(0)

        case "auto":
            let limit = Double(argument ?? "") ?? AppModel.searchWindow + 30
            let model = AppModel.shared
            var outcome: Int32?
            var sawSearch = false
            model.onPhaseChange = { phase in
                switch phase {
                case .searching, .pairing, .connecting: sawSearch = true
                case .connected(let status) where status.wireless: outcome = 0
                case .connected: outcome = 2
                case .failed, .needsPermission, .bluetoothOff, .bluetoothUnavailable: outcome = 1
                case .idle: if sawSearch { outcome = 3 }
                case .starting: break
                }
            }
            model.start()
            spin(until: { outcome != nil }, limit: limit)
            print("result: \(model.phase)")
            finish(outcome ?? 4)

        case "pair", "connect":
            guard let address = argument else { usage() }
            var code: Int32?
            if command == "pair" {
                driver.pair(address: address) { code = $0 }
            } else {
                driver.connect(address: address) { code = $0 }
            }
            spin(until: { code != nil }, limit: 40)
            let result = code ?? IOCode.timeout
            print("\(command): \(IOCode.hex(result)) \(BluetoothErrorText.describe(result))")
            if let after = driver.snapshot(address: address) { print(line(after)) }
            finish(result == IOCode.success ? 0 : 1)

        case "disconnect":
            guard let address = argument else { usage() }
            let result = driver.disconnect(address: address)
            print("disconnect: \(IOCode.hex(result))")
            finish(result == IOCode.success ? 0 : 1)

        case "forget":
            guard let address = argument else { usage() }
            let removed = driver.forget(address: address)
            spin(1.0)
            print("forget: \(removed)")
            finish(removed ? 0 : 1)

        default:
            usage()
        }
    }

    private static let sharedDriver = BluetoothDriver()

    private static func line(_ device: DeviceSnapshot) -> String {
        let name = device.name ?? "(no name)"
        let cod = "0x" + String(device.classOfDevice, radix: 16)
        return "\(device.address)  \(name)  class=\(cod)  paired=\(device.paired)  connected=\(device.connected)"
    }

    private static func usage() -> Never {
        print("usage: DS4Link --cli status | scan [seconds] | auto [seconds] | pair|connect|disconnect|forget <address>")
        finish(64)
    }

    private static func finish(_ code: Int32) -> Never {
        Log.flush()
        exit(code)
    }

    private static func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func spin(until condition: () -> Bool, limit: TimeInterval) {
        let end = Date().addingTimeInterval(limit)
        while !condition(), Date() < end {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
    }
}
