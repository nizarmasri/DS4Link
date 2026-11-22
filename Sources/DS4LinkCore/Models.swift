import Foundation

/// Buttons on a PlayStation-style pad, used both for the live input test and for
/// highlighting which buttons to hold in the on-screen instructions.
public enum PadButton: String, CaseIterable, Hashable, Sendable {
    case cross, circle, square, triangle
    case up, down, left, right
    case l1, r1, l2, r2, l3, r3
    case share, options, ps, touchpad

    public var label: String {
        switch self {
        case .cross: return "Cross"
        case .circle: return "Circle"
        case .square: return "Square"
        case .triangle: return "Triangle"
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .l1: return "L1"
        case .r1: return "R1"
        case .l2: return "L2"
        case .r2: return "R2"
        case .l3: return "L3"
        case .r3: return "R3"
        case .share: return "Share"
        case .options: return "Options"
        case .ps: return "PS"
        case .touchpad: return "Touchpad"
        }
    }
}

public struct PadInput: Equatable, Sendable {
    public var pressed: Set<PadButton>
    public var leftX: Double
    public var leftY: Double
    public var rightX: Double
    public var rightY: Double

    public init(pressed: Set<PadButton> = [], leftX: Double = 0, leftY: Double = 0, rightX: Double = 0, rightY: Double = 0) {
        self.pressed = pressed
        self.leftX = leftX
        self.leftY = leftY
        self.rightX = rightX
        self.rightY = rightY
    }

    public static let empty = PadInput()
}

/// One Bluetooth device as the system reports it right now.
public struct DeviceSnapshot: Equatable, Sendable {
    public var address: String
    public var name: String?
    public var classOfDevice: UInt32
    public var paired: Bool
    public var connected: Bool

    public init(address: String, name: String?, classOfDevice: UInt32, paired: Bool, connected: Bool) {
        self.address = address
        self.name = name
        self.classOfDevice = classOfDevice
        self.paired = paired
        self.connected = connected
    }
}

/// A controller that macOS has registered with the GameController framework (USB or Bluetooth).
public struct GamepadSnapshot: Equatable, Sendable {
    public var name: String
    public var batteryPercent: Int?
    public var charging: Bool
    public var hasLight: Bool

    public init(name: String, batteryPercent: Int?, charging: Bool, hasLight: Bool) {
        self.name = name
        self.batteryPercent = batteryPercent
        self.charging = charging
        self.hasLight = hasLight
    }
}

public enum AuthState: Sendable { case notDetermined, denied, allowed }
public enum PowerState: Sendable { case unknown, off, on, unsupported }

/// A pairing attempt that is currently in flight.
public enum PadOperation: Equatable, Sendable {
    case pairing(name: String)
    case connecting(name: String)
}

public struct PadFailure: Equatable, Sendable {
    public var title: String
    public var detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

public struct ControllerStatus: Equatable, Sendable {
    public var name: String
    public var wireless: Bool
    public var batteryPercent: Int?
    public var charging: Bool
    /// macOS exposes it to games (GameController framework has picked it up).
    public var registered: Bool
    public var hasLight: Bool

    public init(name: String, wireless: Bool, batteryPercent: Int?, charging: Bool, registered: Bool, hasLight: Bool) {
        self.name = name
        self.wireless = wireless
        self.batteryPercent = batteryPercent
        self.charging = charging
        self.registered = registered
        self.hasLight = hasLight
    }
}

/// What the window shows. Always derived from an `Observation`, never mutated piecemeal.
public enum Phase: Equatable, Sendable {
    case starting
    case needsPermission
    case bluetoothOff
    case bluetoothUnavailable
    case searching(knownName: String?)
    case pairing(name: String)
    case connecting(name: String)
    case connected(ControllerStatus)
    case idle(knownName: String?)
    case failed(PadFailure)
}

/// Everything the app knows at one instant: system ground truth plus what it is doing itself.
public struct Observation: Sendable {
    public var auth: AuthState
    public var power: PowerState
    /// Paired devices that look like game controllers.
    public var controllers: [DeviceSnapshot]
    public var gamepad: GamepadSnapshot?
    public var operation: PadOperation?
    public var searching: Bool
    public var failure: PadFailure?

    public init(
        auth: AuthState,
        power: PowerState,
        controllers: [DeviceSnapshot] = [],
        gamepad: GamepadSnapshot? = nil,
        operation: PadOperation? = nil,
        searching: Bool = false,
        failure: PadFailure? = nil
    ) {
        self.auth = auth
        self.power = power
        self.controllers = controllers
        self.gamepad = gamepad
        self.operation = operation
        self.searching = searching
        self.failure = failure
    }
}

public enum PhaseLogic {
    /// Ground truth wins: a live Bluetooth link shows as connected no matter what the app
    /// thought it was doing, so the window can never get stuck on a stale state.
    public static func derive(_ o: Observation) -> Phase {
        switch o.auth {
        case .denied: return .needsPermission
        case .notDetermined: return .starting
        case .allowed: break
        }
        switch o.power {
        case .off: return .bluetoothOff
        case .unsupported: return .bluetoothUnavailable
        case .unknown: return .starting
        case .on: break
        }

        if let live = o.controllers.first(where: { $0.connected }) {
            return .connected(ControllerStatus(
                name: ControllerMatcher.displayName(live.name),
                wireless: true,
                batteryPercent: o.gamepad?.batteryPercent,
                charging: o.gamepad?.charging ?? false,
                registered: o.gamepad != nil,
                hasLight: o.gamepad?.hasLight ?? false
            ))
        }

        if let operation = o.operation {
            switch operation {
            case .pairing(let name): return .pairing(name: name)
            case .connecting(let name): return .connecting(name: name)
            }
        }

        if let failure = o.failure { return .failed(failure) }

        let known = o.controllers.first.map { ControllerMatcher.displayName($0.name) }
        if o.searching { return .searching(knownName: known) }

        // Registered with macOS but no Bluetooth link: it is plugged in with a cable.
        if let pad = o.gamepad {
            return .connected(ControllerStatus(
                name: pad.name,
                wireless: false,
                batteryPercent: pad.batteryPercent,
                charging: pad.charging,
                registered: true,
                hasLight: pad.hasLight
            ))
        }

        return .idle(knownName: known)
    }
}
