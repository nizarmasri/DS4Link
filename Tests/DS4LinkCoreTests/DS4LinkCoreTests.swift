import XCTest
@testable import DS4LinkCore

final class ControllerMatcherTests: XCTestCase {
    func testDualShockClassOfDeviceIsAController() {
        // 0x002508: major Peripheral (5), minor Gamepad (2). What a DualShock 4 reports.
        XCTAssertTrue(ControllerMatcher.isGameController(name: nil, classOfDevice: 0x002508))
        XCTAssertTrue(ControllerMatcher.isGameController(name: nil, classOfDevice: 0x002504)) // joystick
    }

    func testNamesAreRecognisedWhenClassIsMissing() {
        XCTAssertTrue(ControllerMatcher.isGameController(name: "Wireless Controller", classOfDevice: 0))
        XCTAssertTrue(ControllerMatcher.isGameController(name: "DUALSHOCK 4 Wireless Controller", classOfDevice: 0))
        XCTAssertTrue(ControllerMatcher.isGameController(name: "DualSense Wireless Controller", classOfDevice: 0))
    }

    func testOtherDevicesAreNotControllers() {
        XCTAssertFalse(ControllerMatcher.isGameController(name: "Keychron K3", classOfDevice: 0x002540)) // keyboard
        XCTAssertFalse(ControllerMatcher.isGameController(name: "MX Master", classOfDevice: 0x002580))   // mouse
        XCTAssertFalse(ControllerMatcher.isGameController(name: "WH-1000XM5", classOfDevice: 0x240404))  // headset
        XCTAssertFalse(ControllerMatcher.isGameController(name: "JBL Flip 5", classOfDevice: 0x240414))
        XCTAssertFalse(ControllerMatcher.isGameController(name: nil, classOfDevice: 0x5A020C))           // phone
        XCTAssertFalse(ControllerMatcher.isGameController(name: nil, classOfDevice: 0))
    }

    func testKeyboardClassBeatsAMisleadingName() {
        XCTAssertFalse(ControllerMatcher.isGameController(name: "Xbox Chatpad", classOfDevice: 0x002540))
    }

    func testDisplayNames() {
        XCTAssertEqual(ControllerMatcher.displayName("Wireless Controller"), "DualShock 4")
        XCTAssertEqual(ControllerMatcher.displayName("DUALSHOCK 4 Wireless Controller"), "DualShock 4")
        XCTAssertEqual(ControllerMatcher.displayName("DualSense Wireless Controller"), "DualSense")
        XCTAssertEqual(ControllerMatcher.displayName("DualSense Edge Wireless Controller"), "DualSense Edge")
        XCTAssertEqual(ControllerMatcher.displayName("8BitDo Pro 2"), "8BitDo Pro 2")
        XCTAssertEqual(ControllerMatcher.displayName(nil), "Wireless Controller")
    }
}

final class PhaseLogicTests: XCTestCase {
    private let pad = DeviceSnapshot(address: "aa-bb-cc-dd-ee-ff", name: "Wireless Controller", classOfDevice: 0x002508, paired: true, connected: false)
    private var livePad: DeviceSnapshot { var copy = pad; copy.connected = true; return copy }
    private let registered = GamepadSnapshot(name: "DualShock 4", batteryPercent: 60, charging: false, hasLight: true)

    func testPermissionAndPowerComeFirst() {
        XCTAssertEqual(PhaseLogic.derive(Observation(auth: .denied, power: .on, controllers: [livePad])), .needsPermission)
        XCTAssertEqual(PhaseLogic.derive(Observation(auth: .notDetermined, power: .on)), .starting)
        XCTAssertEqual(PhaseLogic.derive(Observation(auth: .allowed, power: .off, controllers: [livePad])), .bluetoothOff)
        XCTAssertEqual(PhaseLogic.derive(Observation(auth: .allowed, power: .unsupported)), .bluetoothUnavailable)
        XCTAssertEqual(PhaseLogic.derive(Observation(auth: .allowed, power: .unknown)), .starting)
    }

    func testLiveLinkBeatsEverythingTheAppThinksItIsDoing() {
        let phase = PhaseLogic.derive(Observation(
            auth: .allowed, power: .on, controllers: [livePad], gamepad: registered,
            operation: .pairing(name: "DualShock 4"), searching: true,
            failure: PadFailure(title: "x", detail: "y")
        ))
        guard case .connected(let status) = phase else { return XCTFail("expected connected, got \(phase)") }
        XCTAssertTrue(status.wireless)
        XCTAssertTrue(status.registered)
        XCTAssertEqual(status.batteryPercent, 60)
        XCTAssertEqual(status.name, "DualShock 4")
    }

    func testLinkedButNotYetRegistered() {
        let phase = PhaseLogic.derive(Observation(auth: .allowed, power: .on, controllers: [livePad]))
        guard case .connected(let status) = phase else { return XCTFail("expected connected") }
        XCTAssertTrue(status.wireless)
        XCTAssertFalse(status.registered)
        XCTAssertNil(status.batteryPercent)
    }

    func testOperationThenFailureThenSearch() {
        XCTAssertEqual(
            PhaseLogic.derive(Observation(auth: .allowed, power: .on, operation: .connecting(name: "DualShock 4"), searching: true)),
            .connecting(name: "DualShock 4")
        )
        let failure = PadFailure(title: "t", detail: "d")
        XCTAssertEqual(
            PhaseLogic.derive(Observation(auth: .allowed, power: .on, controllers: [pad], failure: failure)),
            .failed(failure)
        )
        XCTAssertEqual(
            PhaseLogic.derive(Observation(auth: .allowed, power: .on, controllers: [pad], searching: true)),
            .searching(knownName: "DualShock 4")
        )
        XCTAssertEqual(
            PhaseLogic.derive(Observation(auth: .allowed, power: .on, searching: true)),
            .searching(knownName: nil)
        )
    }

    func testCabledPadAndIdle() {
        let cabled = PhaseLogic.derive(Observation(auth: .allowed, power: .on, controllers: [pad], gamepad: registered))
        guard case .connected(let status) = cabled else { return XCTFail("expected connected") }
        XCTAssertFalse(status.wireless)

        // A user-requested search shows even while the pad is still on its cable.
        XCTAssertEqual(
            PhaseLogic.derive(Observation(auth: .allowed, power: .on, gamepad: registered, searching: true)),
            .searching(knownName: nil)
        )
        XCTAssertEqual(PhaseLogic.derive(Observation(auth: .allowed, power: .on, controllers: [pad])), .idle(knownName: "DualShock 4"))
        XCTAssertEqual(PhaseLogic.derive(Observation(auth: .allowed, power: .on)), .idle(knownName: nil))
    }
}

final class BluetoothErrorTextTests: XCTestCase {
    func testKnownCodesReadAsSentences() {
        XCTAssertEqual(BluetoothErrorText.describe(0x04), "The controller stopped listening")
        XCTAssertEqual(BluetoothErrorText.describe(IOCode.timeout), "Pairing timed out")
        XCTAssertEqual(BluetoothErrorText.describe(IOCode.busy), "Bluetooth was busy")
    }

    func testUnknownCodesKeepTheNumber() {
        XCTAssertEqual(BluetoothErrorText.describe(0x77), "Bluetooth reported error 0x77")
        XCTAssertEqual(IOCode.hex(IOCode.timeout), "0xE00002D6")
    }
}
