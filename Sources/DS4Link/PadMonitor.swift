import Foundation
import GameController
import DS4LinkCore

/// Preset light bar colours. PlayStation pads expose the light through GameController.
enum LightPreset: String, CaseIterable, Identifiable {
    case blue, red, green, pink, orange, white

    var id: String { rawValue }

    var rgb: (Float, Float, Float) {
        switch self {
        case .blue: return (0.0, 0.25, 1.0)
        case .red: return (1.0, 0.05, 0.05)
        case .green: return (0.0, 1.0, 0.2)
        case .pink: return (1.0, 0.1, 0.6)
        case .orange: return (1.0, 0.4, 0.0)
        case .white: return (1.0, 1.0, 1.0)
        }
    }
}

/// Watches the GameController framework: the proof that macOS (and therefore games) can
/// actually use the pad, plus battery level, light bar and live button state.
final class PadMonitor {
    var onChange: (() -> Void)?
    var onInput: ((PadInput) -> Void)?

    private(set) var controller: GCController?
    private var tokens: [NSObjectProtocol] = []

    func start() {
        guard tokens.isEmpty else { return }
        GCController.shouldMonitorBackgroundEvents = true
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            let pad = note.object as? GCController
            Log.info("gamepad registered: \(pad?.vendorName ?? "?") [\(pad?.productCategory ?? "?")]")
            self?.adopt()
        })
        tokens.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            let pad = note.object as? GCController
            Log.info("gamepad unregistered: \(pad?.vendorName ?? "?")")
            self?.adopt()
        })
        adopt()
    }

    private func adopt() {
        let all = GCController.controllers()
        let next = all.first { $0.extendedGamepad != nil } ?? all.first
        if next !== controller {
            controller?.extendedGamepad?.valueChangedHandler = nil
            controller = next
            next?.extendedGamepad?.valueChangedHandler = { [weak self] gamepad, _ in
                self?.onInput?(Self.read(gamepad))
            }
            onInput?(.empty)
        }
        onChange?()
    }

    var snapshot: GamepadSnapshot? {
        guard let controller else { return nil }
        var percent: Int?
        var charging = false
        if let battery = controller.battery {
            charging = battery.batteryState == .charging
            if battery.batteryState != .unknown || battery.batteryLevel > 0 {
                percent = max(0, min(100, Int((battery.batteryLevel * 100).rounded())))
            }
        }
        return GamepadSnapshot(
            name: ControllerMatcher.displayName(controller.vendorName ?? controller.productCategory),
            batteryPercent: percent,
            charging: charging,
            hasLight: controller.light != nil
        )
    }

    func setLight(_ preset: LightPreset) {
        let (red, green, blue) = preset.rgb
        controller?.light?.color = GCColor(red: red, green: green, blue: blue)
    }

    private static func read(_ pad: GCExtendedGamepad) -> PadInput {
        var pressed = Set<PadButton>()
        func add(_ button: PadButton, _ input: GCControllerButtonInput?) {
            if input?.isPressed == true { pressed.insert(button) }
        }
        add(.cross, pad.buttonA)
        add(.circle, pad.buttonB)
        add(.square, pad.buttonX)
        add(.triangle, pad.buttonY)
        add(.up, pad.dpad.up)
        add(.down, pad.dpad.down)
        add(.left, pad.dpad.left)
        add(.right, pad.dpad.right)
        add(.l1, pad.leftShoulder)
        add(.r1, pad.rightShoulder)
        add(.l2, pad.leftTrigger)
        add(.r2, pad.rightTrigger)
        add(.l3, pad.leftThumbstickButton)
        add(.r3, pad.rightThumbstickButton)
        add(.options, pad.buttonMenu)
        add(.share, pad.buttonOptions)
        add(.ps, pad.buttonHome)
        if let dualShock = pad as? GCDualShockGamepad {
            add(.touchpad, dualShock.touchpadButton)
        } else if let dualSense = pad as? GCDualSenseGamepad {
            add(.touchpad, dualSense.touchpadButton)
        }
        return PadInput(
            pressed: pressed,
            leftX: Double(pad.leftThumbstick.xAxis.value),
            leftY: Double(pad.leftThumbstick.yAxis.value),
            rightX: Double(pad.rightThumbstick.xAxis.value),
            rightY: Double(pad.rightThumbstick.yAxis.value)
        )
    }
}
