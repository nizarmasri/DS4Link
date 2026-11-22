import AppKit
import Combine
import DS4LinkCore

/// The engine. Once a second it re-reads ground truth (permission, radio power, paired
/// controllers, what macOS has registered as a gamepad) and derives the phase from that, so the
/// window cannot drift out of sync with reality. Searching and pairing run alongside with their
/// own deadlines and are simply abandoned the moment a live connection shows up, however it was
/// made: by this app, by pressing PS, or by hand in System Settings.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    static let searchWindow: TimeInterval = 120
    /// How long one inquiry runs before it is wrapped up and a fresh one started.
    static let inquiryCycle: TimeInterval = 10
    static let maxAttempts = 3
    private static let rememberedKey = "lastControllerAddress"

    @Published private(set) var phase: Phase = .starting
    @Published private(set) var secondsLeft = 0
    @Published private(set) var searchElapsed = 0
    @Published private(set) var settling = false
    @Published private(set) var note: String?
    @Published private(set) var input: PadInput = .empty
    @Published private(set) var preparingShare = false
    @Published var shareArchive: URL?
    @Published var alertMessage: String?

    /// Used by the command-line test mode to print transitions.
    var onPhaseChange: ((Phase) -> Void)?

    private let driver = BluetoothDriver()
    private let authority = BluetoothAuthority()
    private let pads = PadMonitor()
    private var timer: Timer?
    private var started = false

    private var searchDeadline: Date?
    private var searchStartedAt: Date?
    private var userInitiatedSearch = false
    private var inquiryStartedAt: Date?
    private var inquiryFinishingSince: Date?
    private var reportedNearby: [String: String] = [:]
    private var nextInquiryAt = Date.distantPast
    private var inquiryCount = 0
    private var attempts = 0

    private var operation: PadOperation?
    private var operationAddress: String?
    private var verifyDeadline: Date?
    private var verifyFailureCode = IOCode.timeout
    private var failure: PadFailure?

    private var readySince: Date?
    private var didAutoSearch = false
    private var watchingConnections = false
    private var connectedSince: Date?
    private var noteExpiry: Date?
    private var loggedAuth: AuthState?
    private var loggedPower: PowerState?

    var viewState: ViewState {
        ViewState(
            phase: phase,
            secondsLeft: secondsLeft,
            searchElapsed: searchElapsed,
            settling: settling,
            note: note,
            input: input,
            preparingShare: preparingShare
        )
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        Log.info("DS4Link \(version) starting, macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        authority.onChange = { [weak self] in self?.refresh() }
        pads.onChange = { [weak self] in self?.refresh() }
        pads.onInput = { [weak self] in self?.input = $0 }
        driver.onFound = { [weak self] in self?.handleFound($0) }
        driver.onInquiryFinished = { [weak self] error, _ in self?.handleInquiryFinished(error: error) }
        driver.onConnectionEvent = { [weak self] in self?.refresh() }

        authority.start()
        pads.start()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    // MARK: Ground truth

    private var rememberedAddress: String? {
        get { UserDefaults.standard.string(forKey: Self.rememberedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.rememberedKey) }
    }

    /// Paired controllers, including the one being set up right now and the last one that worked
    /// even if its name or class would not be recognised. Connected ones first.
    private func knownControllers() -> [DeviceSnapshot] {
        var list = driver.pairedControllers()
        for address in [operationAddress, rememberedAddress].compactMap({ $0 })
        where !list.contains(where: { $0.address == address }) {
            if let extra = driver.snapshot(address: address), extra.paired { list.append(extra) }
        }
        return list.sorted { $0.connected && !$1.connected }
    }

    func refresh() {
        let auth = authority.auth
        let power = authority.power
        let ready = auth == .allowed && power == .on
        if auth != loggedAuth || power != loggedPower {
            Log.info("bluetooth: permission=\(auth) radio=\(power)")
            loggedAuth = auth
            loggedPower = power
        }

        if ready {
            if readySince == nil { readySince = Date() }
            if !watchingConnections {
                watchingConnections = true
                driver.startWatchingConnections()
            }
        } else {
            readySince = nil
            if searchDeadline != nil || operation != nil {
                Log.warn("bluetooth became unavailable, abandoning search")
                abandonOperation()
                finishSearch()
            }
        }

        let controllers = ready ? knownControllers() : []
        let gamepad = pads.snapshot
        let live = controllers.first { $0.connected }

        if let live {
            if searchDeadline != nil || operation != nil {
                Log.info("controller is connected, search finished")
                abandonOperation(cancelDriver: false)
                finishSearch()
            }
            failure = nil
            if rememberedAddress != live.address { rememberedAddress = live.address }
            if connectedSince == nil { connectedSince = Date() }
        } else {
            connectedSince = nil
        }
        let nowSettling = connectedSince.map { Date().timeIntervalSince($0) < 12 } ?? false
        if nowSettling != settling { settling = nowSettling }

        // One automatic search per launch, once Bluetooth has been usable for a moment
        // (long enough for a cabled pad to register, so we do not search needlessly).
        if ready, !didAutoSearch, let since = readySince, Date().timeIntervalSince(since) >= 0.8 {
            didAutoSearch = true
            if live == nil, gamepad == nil {
                beginSearch(userInitiated: false)
                return
            }
        }

        // An automatic search gives way to a pad that turns out to be plugged in by cable.
        if searchDeadline != nil, !userInitiatedSearch, operation == nil, live == nil, gamepad != nil {
            Log.info("pad is connected by cable, stopping automatic search")
            finishSearch()
        }

        var next = PhaseLogic.derive(Observation(
            auth: auth,
            power: power,
            controllers: controllers,
            gamepad: gamepad,
            operation: operation,
            searching: searchDeadline != nil,
            failure: failure
        ))
        // Until the launch-time search decision is made, "idle" would only flash by.
        if ready, !didAutoSearch, case .idle = next { next = .starting }
        if next != phase {
            Log.info("phase: \(Self.summary(next))")
            phase = next
            onPhaseChange?(next)
        }
    }

    private func tick() {
        if let expiry = noteExpiry, Date() >= expiry {
            note = nil
            noteExpiry = nil
        }
        refresh()

        guard let deadline = searchDeadline else { return }
        let now = Date()
        let left = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
        if left != secondsLeft { secondsLeft = left }
        let elapsed = Int(now.timeIntervalSince(searchStartedAt ?? now))
        if elapsed != searchElapsed { searchElapsed = elapsed }

        if operation != nil {
            if let verify = verifyDeadline, now >= verify {
                attemptFailed(stage: "verify", code: verifyFailureCode)
            }
            return
        }
        if now >= deadline {
            Log.info("search window ended without a controller")
            finishSearch()
            refresh()
            return
        }
        if let began = inquiryStartedAt {
            // Found-device callbacks are unreliable on current macOS, so read the list directly.
            driver.foundDevices().forEach(handleFound)
            guard operation == nil, inquiryStartedAt != nil else { return }
            if let finishing = inquiryFinishingSince {
                // Asked it to wrap up; if completion never arrives, cut it off and move on.
                if now.timeIntervalSince(finishing) > 5 {
                    driver.stopInquiry()
                    endInquiryCycle()
                }
            } else if now.timeIntervalSince(began) >= Self.inquiryCycle {
                inquiryFinishingSince = now
                driver.finishInquiry()
            }
            return
        }
        if now >= nextInquiryAt { startInquiry() }
    }

    // MARK: Searching

    func beginSearch(userInitiated: Bool) {
        guard authority.auth == .allowed, authority.power == .on else { return }
        guard operation == nil else { return }
        Log.info("search started (\(userInitiated ? "by user" : "automatic"))")
        failure = nil
        attempts = 0
        inquiryCount = 0
        reportedNearby = [:]
        userInitiatedSearch = userInitiated
        searchStartedAt = Date()
        searchDeadline = Date().addingTimeInterval(Self.searchWindow)
        secondsLeft = Int(Self.searchWindow)
        searchElapsed = 0
        nextInquiryAt = .distantPast
        if inquiryStartedAt == nil { startInquiry() }
        refresh()
    }

    func cancelSearch() {
        guard operation == nil, searchDeadline != nil else { return }
        Log.info("search cancelled by user")
        finishSearch()
        refresh()
    }

    private func finishSearch() {
        searchDeadline = nil
        searchStartedAt = nil
        if secondsLeft != 0 { secondsLeft = 0 }
        if searchElapsed != 0 { searchElapsed = 0 }
        if inquiryStartedAt != nil {
            driver.stopInquiry()
            inquiryStartedAt = nil
            inquiryFinishingSince = nil
        }
    }

    private func startInquiry() {
        inquiryCount += 1
        // Class of Device identifies a pad instantly. Names are also resolved, to catch clones
        // that report an unusual class.
        let result = driver.startInquiry(resolveNames: true)
        if result == IOCode.success {
            inquiryStartedAt = Date()
            inquiryFinishingSince = nil
            if inquiryCount == 1 || inquiryCount % 4 == 0 { Log.info("scanning (cycle \(inquiryCount))") }
        } else {
            nextInquiryAt = Date().addingTimeInterval(2)
        }
    }

    private func endInquiryCycle() {
        inquiryStartedAt = nil
        inquiryFinishingSince = nil
        nextInquiryAt = Date().addingTimeInterval(0.5)
    }

    private func handleInquiryFinished(error: Int32) {
        if error != IOCode.success { Log.warn("inquiry ended with \(IOCode.hex(error))") }
        endInquiryCycle()
    }

    private func handleFound(_ device: DeviceSnapshot) {
        let isController = ControllerMatcher.isGameController(name: device.name, classOfDevice: device.classOfDevice)
        // Polled every second, so only log a device when it is new or something about it changed.
        let description = "name=\(device.name ?? "?") class=0x\(String(device.classOfDevice, radix: 16)) paired=\(device.paired) controller=\(isController)"
        if reportedNearby[device.address] != description {
            reportedNearby[device.address] = description
            Log.info("nearby: \(device.address) \(description)")
        }
        guard isController, searchDeadline != nil, operation == nil else { return }

        // Only a pad in pairing mode answers an inquiry, so it wants a fresh pairing even if this
        // Mac still holds an old record for it (which would now be stale and must go first).
        let name = ControllerMatcher.displayName(device.name)
        let address = device.address
        attempts += 1
        operation = .pairing(name: name)
        operationAddress = address
        verifyDeadline = nil
        driver.stopInquiry()
        inquiryStartedAt = nil
        inquiryFinishingSince = nil
        Log.info("pairing attempt \(attempts) with \(address) (\(name))")
        refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.operationAddress == address else { return }
            if device.paired {
                Log.info("removing the old pairing record first")
                self.driver.forget(address: address)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.pairNow(address: address, name: name)
                }
            } else {
                self.pairNow(address: address, name: name)
            }
        }
    }

    private func pairNow(address: String, name: String) {
        guard operationAddress == address else { return }
        driver.pair(address: address) { [weak self] code in
            guard let self, self.operationAddress == address else { return }
            guard code == IOCode.success else {
                self.attemptFailed(stage: "pair", code: code)
                return
            }
            self.operation = .connecting(name: name)
            self.refresh()
            self.driver.connect(address: address) { [weak self] code in
                guard let self, self.operationAddress == address else { return }
                // Success or not, the pad often finishes the link itself a moment later, so give
                // ground truth a few seconds before calling the attempt a failure.
                self.verifyFailureCode = code == IOCode.success ? IOCode.timeout : code
                self.verifyDeadline = Date().addingTimeInterval(code == IOCode.success ? 12 : 6)
                self.refresh()
            }
        }
    }

    private func abandonOperation(cancelDriver: Bool = true) {
        if cancelDriver, operation != nil {
            driver.cancelPairing()
            driver.cancelConnect()
        }
        operation = nil
        operationAddress = nil
        verifyDeadline = nil
    }

    private func attemptFailed(stage: String, code: Int32) {
        let reason = BluetoothErrorText.describe(code)
        Log.warn("attempt \(attempts) failed at \(stage): \(IOCode.hex(code)) (\(reason))")
        abandonOperation()

        let timeLeft = searchDeadline?.timeIntervalSinceNow ?? 0
        if attempts < Self.maxAttempts, timeLeft > 8 {
            showNote("\(reason). Trying again…", seconds: 6)
            nextInquiryAt = Date().addingTimeInterval(1.5)
        } else {
            finishSearch()
            failure = PadFailure(
                title: "Couldn't pair the controller",
                detail: "\(reason). Switch the controller off (hold PS for 10 seconds), then hold SHARE + PS until the light flashes quickly, and try again."
            )
        }
        refresh()
    }

    // MARK: User actions

    func turnOffController() {
        let live = knownControllers().filter { $0.connected }
        guard !live.isEmpty else { return }
        for device in live { driver.disconnect(address: device.address) }
        showNote("Controller switched off. Press PS to wake it.", seconds: 6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refresh() }
    }

    func forgetControllers() {
        abandonOperation()
        finishSearch()
        failure = nil
        var removedAll = true
        for device in knownControllers() where !driver.forget(address: device.address) {
            removedAll = false
        }
        rememberedAddress = nil
        if !removedAll {
            alertMessage = "This version of macOS would not let DS4Link remove the pairing. Open Bluetooth Settings and choose Forget This Device next to the controller."
        } else {
            showNote("Controller forgotten.", seconds: 5)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refresh() }
    }

    func turnBluetoothOn() {
        let asked = BluetoothDriver.powerOn()
        Log.info("asked macOS to switch Bluetooth on: \(asked)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.refresh()
            if self.phase == .bluetoothOff { self.openBluetoothSettings() }
        }
    }

    func openBluetoothSettings() {
        open("x-apple.systempreferences:com.apple.BluetoothSettings")
    }

    func openPrivacySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
    }

    private func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    func setLight(_ preset: LightPreset) {
        pads.setLight(preset)
    }

    func showLog() {
        NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
    }

    /// Packs this very app into a zip (with install notes) ready to send to another Mac.
    func prepareShare() {
        guard !preparingShare else { return }
        preparingShare = true
        let bundle = Bundle.main.bundleURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try ShareExporter.makeArchive(from: bundle) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.preparingShare = false
                switch result {
                case .success(let url):
                    Log.info("share archive ready: \(url.path)")
                    self.shareArchive = url
                case .failure(let error):
                    Log.error("share archive failed: \(error.localizedDescription)")
                    self.alertMessage = "Couldn't prepare the copy: \(error.localizedDescription)"
                }
            }
        }
    }

    func perform(_ action: ActionID) {
        switch action {
        case .search: beginSearch(userInitiated: true)
        case .cancelSearch: cancelSearch()
        case .turnOff: turnOffController()
        case .bluetoothSettings: openBluetoothSettings()
        case .privacySettings: openPrivacySettings()
        case .bluetoothOn: turnBluetoothOn()
        case .share: prepareShare()
        case .light(let preset): setLight(preset)
        case .forget: break   // needs confirmation, handled by the window
        }
    }

    // MARK: Helpers

    private func showNote(_ text: String, seconds: TimeInterval) {
        note = text
        noteExpiry = Date().addingTimeInterval(seconds)
    }

    private static func summary(_ phase: Phase) -> String {
        switch phase {
        case .starting: return "starting"
        case .needsPermission: return "needs Bluetooth permission"
        case .bluetoothOff: return "bluetooth off"
        case .bluetoothUnavailable: return "no bluetooth hardware"
        case .searching(let known): return "searching (known: \(known ?? "none"))"
        case .pairing(let name): return "pairing \(name)"
        case .connecting(let name): return "connecting \(name)"
        case .connected(let status):
            let battery = status.batteryPercent.map { "\($0)%" } ?? "?"
            return "connected \(status.name) wireless=\(status.wireless) registered=\(status.registered) battery=\(battery)"
        case .idle(let known): return "idle (known: \(known ?? "none"))"
        case .failed(let failure): return "failed: \(failure.title): \(failure.detail)"
        }
    }
}
