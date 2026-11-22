import DS4LinkCore
import SwiftUI

/// Everything the window needs to draw one frame. A plain value, so every screen can be
/// rendered from canned data (see PreviewRenderer) without any Bluetooth involved.
struct ViewState: Equatable {
    var phase: Phase
    var secondsLeft = 0
    var searchElapsed = 0
    var settling = false
    var note: String?
    var input: PadInput = .empty
    var preparingShare = false

    var hasKnownController: Bool {
        switch phase {
        case .connected(let status): return status.wireless
        case .idle(let known), .searching(let known): return known != nil
        default: return false
        }
    }
}

enum ActionID: Equatable {
    case search
    case cancelSearch
    case turnOff
    case bluetoothSettings
    case privacySettings
    case bluetoothOn
    case forget
    case share
    case light(LightPreset)
}

enum Tone {
    case neutral, active, good, warn, bad

    var color: Color {
        switch self {
        case .neutral: return Color(red: 0.55, green: 0.57, blue: 0.63)
        case .active: return Color(red: 0.16, green: 0.46, blue: 1.0)
        case .good: return Color(red: 0.13, green: 0.70, blue: 0.40)
        case .warn: return Color(red: 0.95, green: 0.58, blue: 0.10)
        case .bad: return Color(red: 0.92, green: 0.28, blue: 0.27)
        }
    }
}

enum Palette {
    static func window(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.098, green: 0.102, blue: 0.118) : Color(red: 0.957, green: 0.961, blue: 0.972)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.white
    }

    static func cardStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }

    static func padBody(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.26, green: 0.275, blue: 0.315) : Color(red: 0.155, green: 0.165, blue: 0.195)
    }

    static func padDetail(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.42, green: 0.44, blue: 0.50) : Color(red: 0.33, green: 0.35, blue: 0.41)
    }

    static func padRecess(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.17, green: 0.18, blue: 0.21) : Color(red: 0.085, green: 0.09, blue: 0.11)
    }
}

struct ButtonSpec: Equatable {
    var label: String
    var action: ActionID
}

/// Words and emphasis for a phase. Kept apart from the views so the copy is in one place.
struct Presentation: Equatable {
    var tone: Tone
    var pill: String
    var title: String
    var subtitle: String
    var busy = false
    var hinted: Set<PadButton> = []
    var primary: ButtonSpec?
    var secondary: ButtonSpec?

    static func make(_ state: ViewState) -> Presentation {
        switch state.phase {
        case .starting:
            return Presentation(
                tone: .neutral, pill: "Starting", title: "Getting ready…",
                subtitle: "If macOS asks, click Allow so DS4Link can use Bluetooth.",
                busy: true
            )

        case .needsPermission:
            return Presentation(
                tone: .warn, pill: "Permission needed", title: "Bluetooth access is off",
                subtitle: "DS4Link can't see your controller without it. Switch DS4Link on in Privacy & Security → Bluetooth, then come back.",
                primary: ButtonSpec(label: "Open Privacy Settings", action: .privacySettings)
            )

        case .bluetoothOff:
            return Presentation(
                tone: .warn, pill: "Bluetooth off", title: "Bluetooth is switched off",
                subtitle: "Turn it on and DS4Link starts looking for your controller right away.",
                primary: ButtonSpec(label: "Turn Bluetooth On", action: .bluetoothOn)
            )

        case .bluetoothUnavailable:
            return Presentation(
                tone: .bad, pill: "No Bluetooth", title: "This Mac has no Bluetooth",
                subtitle: "A wireless controller needs Bluetooth. You can still play with the controller plugged in by cable."
            )

        case .searching(let known):
            return Presentation(
                tone: .active, pill: "Searching", title: "Hold SHARE + PS",
                subtitle: known == nil
                    ? "Keep both held until the light bar flashes quickly. DS4Link does the rest."
                    : "Keep both held until the light bar flashes quickly. Paired on this Mac before? Just tap PS instead.",
                busy: true,
                hinted: [.share, .ps],
                secondary: ButtonSpec(label: "Stop Searching", action: .cancelSearch)
            )

        case .pairing(let name):
            return Presentation(
                tone: .active, pill: "Pairing", title: "Found your \(name)",
                subtitle: "Pairing it with this Mac. Keep the controller close for a few seconds.",
                busy: true
            )

        case .connecting(let name):
            return Presentation(
                tone: .active, pill: "Connecting", title: "Connecting \(name)…",
                subtitle: "Almost there. Keep the controller close.",
                busy: true
            )

        case .connected(let status):
            if !status.wireless {
                return Presentation(
                    tone: .good, pill: "Connected by cable", title: "\(status.name) is plugged in",
                    subtitle: "It works like this already. To cut the cord, unplug it and click Go Wireless.",
                    primary: ButtonSpec(label: "Go Wireless", action: .search)
                )
            }
            if !status.registered && !state.settling {
                return Presentation(
                    tone: .warn, pill: "Connected", title: "Connected, but not ready",
                    subtitle: "Bluetooth is linked, yet macOS hasn't registered it as a game controller. Switch it off and tap PS to reconnect.",
                    primary: ButtonSpec(label: "Switch Controller Off", action: .turnOff)
                )
            }
            return Presentation(
                tone: .good, pill: "Connected wirelessly", title: "\(status.name) is ready",
                subtitle: status.registered
                    ? "No cable needed. Press any button and watch it light up above."
                    : "Linked. Finishing setup with macOS…",
                busy: !status.registered,
                secondary: ButtonSpec(label: "Switch Controller Off", action: .turnOff)
            )

        case .idle(let known):
            if let known {
                return Presentation(
                    tone: .neutral, pill: "Controller off", title: "Tap PS to wake your \(known)",
                    subtitle: "It reconnects by itself. Used it with a PS4 or another computer since? Then it has forgotten this Mac, so pair it again.",
                    hinted: [.ps],
                    primary: ButtonSpec(label: "Pair Again", action: .search)
                )
            }
            return Presentation(
                tone: .neutral, pill: "Not connected", title: "No controller found",
                subtitle: "Click Search, then hold SHARE + PS on the controller until its light bar flashes quickly.",
                primary: ButtonSpec(label: "Search for Controller", action: .search)
            )

        case .failed(let failure):
            return Presentation(
                tone: .bad, pill: "Didn't work", title: failure.title,
                subtitle: failure.detail,
                primary: ButtonSpec(label: "Try Again", action: .search),
                secondary: ButtonSpec(label: "Open Bluetooth Settings", action: .bluetoothSettings)
            )
        }
    }
}
