import AppKit
import DS4LinkCore
import SwiftUI

/// The whole window, as a pure function of `ViewState`.
struct ContentView: View {
    static let size = CGSize(width: 440, height: 664)

    let state: ViewState
    let perform: (ActionID) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var light: LightPreset = .blue

    var body: some View {
        let look = Presentation.make(state)
        VStack(spacing: 0) {
            hero(look)
            StatusPill(text: look.pill, tone: look.tone, busy: look.busy)
            Text(look.title)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text(look.subtitle)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.horizontal, 6)
            panel.padding(.top, 16)
            Spacer(minLength: 10)
            if let note = state.note {
                NoteBar(text: note).padding(.bottom, 10)
            }
            buttons(look)
            footer.padding(.top, 14)
        }
        .padding(.horizontal, 26)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Palette.window(scheme))
    }

    // MARK: Hero

    private func hero(_ look: Presentation) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [look.tone.color.opacity(scheme == .dark ? 0.30 : 0.22), look.tone.color.opacity(0)],
                    center: .center, startRadius: 8, endRadius: 150
                ))
                .frame(width: 300, height: 300)
            ControllerArt(
                lightBar: lightBarColor(look),
                accent: look.tone == .neutral ? Tone.active.color : look.tone.color,
                pressed: state.input.pressed,
                hinted: look.hinted,
                leftStick: CGPoint(x: state.input.leftX, y: state.input.leftY),
                rightStick: CGPoint(x: state.input.rightX, y: state.input.rightY),
                showCallouts: !look.hinted.isEmpty
            )
        }
        .frame(height: 216)
        .clipped()
    }

    private func lightBarColor(_ look: Presentation) -> Color {
        switch state.phase {
        case .connected:
            let (red, green, blue) = light.rgb
            return Color(red: Double(red), green: Double(green), blue: Double(blue))
        case .searching, .pairing, .connecting:
            return .white
        default:
            return Palette.padRecess(scheme)
        }
    }

    // MARK: Middle panel

    @ViewBuilder
    private var panel: some View {
        switch state.phase {
        case .searching:
            Card {
                StepRow(number: 1, text: "Start with the controller off (light bar dark).", tint: Tone.active.color)
                StepRow(number: 2, text: "Hold SHARE and PS together for about 3 seconds.", tint: Tone.active.color)
                StepRow(number: 3, text: "Let go when the light flashes in quick double blinks.", tint: Tone.active.color)
                CardDivider()
                if state.searchElapsed >= 40 {
                    TipRow(symbol: "lightbulb.fill", text: "Light pulsing slowly instead? That isn't pairing mode. Hold PS for 10 seconds to switch it off, then try again.")
                    CardDivider()
                }
                HStack(spacing: 9) {
                    Spinner(color: Tone.active.color)
                    Text("Looking nearby…").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(Self.clock(state.secondsLeft))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
            }

        case .pairing, .connecting:
            Card {
                HStack(spacing: 9) {
                    Spinner(color: Tone.active.color)
                    Text("Working on it. This takes a few seconds.").font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
            }

        case .connected(let status):
            Card {
                InfoRow(label: "Battery") {
                    BatteryGauge(percent: status.batteryPercent, charging: status.charging)
                }
                CardDivider()
                InfoRow(label: "Connection") {
                    HStack(spacing: 6) {
                        Image(systemName: status.wireless ? "dot.radiowaves.left.and.right" : "cable.connector")
                            .font(.system(size: 11, weight: .semibold))
                        Text(status.wireless ? "Bluetooth, no cable" : "USB cable")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                if status.hasLight {
                    CardDivider()
                    InfoRow(label: "Light bar") { swatches }
                }
                if status.registered {
                    CardDivider()
                    InfoRow(label: "Button test") {
                        Text(pressedText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(state.input.pressed.isEmpty ? .secondary : Tone.good.color)
                            .lineLimit(1)
                    }
                }
            }

        case .idle(let known):
            if known != nil {
                Card {
                    TipRow(symbol: "power", text: "Tap PS once. The light bar pulses, then turns solid when it's connected.")
                    CardDivider()
                    TipRow(symbol: "arrow.triangle.2.circlepath", text: "A controller remembers only one device. After a PS4 or another computer, pair it again here.")
                }
            } else {
                Card {
                    StepRow(number: 1, text: "Click Search for Controller.", tint: Tone.neutral.color)
                    StepRow(number: 2, text: "Hold SHARE and PS together for about 3 seconds.", tint: Tone.neutral.color)
                    StepRow(number: 3, text: "Let go when the light flashes in quick double blinks.", tint: Tone.neutral.color)
                }
            }

        case .failed:
            Card {
                TipRow(symbol: "arrow.left.and.right", text: "Keep the controller within arm's reach of the Mac.")
                CardDivider()
                TipRow(symbol: "gamecontroller", text: "A PS4 nearby can grab it first. Switch the console fully off.")
                CardDivider()
                TipRow(symbol: "pin", text: "Still stuck? Push the tiny reset button on the back, next to L2, with a paperclip for 5 seconds.")
            }

        case .needsPermission:
            Card {
                TipRow(symbol: "lock.shield", text: "DS4Link only uses Bluetooth to talk to your controller. Nothing leaves this Mac.")
            }

        case .starting, .bluetoothOff, .bluetoothUnavailable:
            EmptyView()
        }
    }

    private var swatches: some View {
        HStack(spacing: 9) {
            ForEach(LightPreset.allCases) { preset in
                let (red, green, blue) = preset.rgb
                Button {
                    light = preset
                    perform(.light(preset))
                } label: {
                    Circle()
                        .fill(Color(red: Double(red), green: Double(green), blue: Double(blue)))
                        .frame(width: 17, height: 17)
                        .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1))
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(light == preset ? 0.85 : 0), lineWidth: 1.6)
                                .frame(width: 23, height: 23)
                        )
                }
                .buttonStyle(.plain)
                .help("Set the light bar to \(preset.rawValue)")
            }
        }
    }

    private var pressedText: String {
        let order = PadButton.allCases.filter { state.input.pressed.contains($0) }
        return order.isEmpty ? "Press any button" : order.map(\.label).joined(separator: " + ")
    }

    // MARK: Buttons

    private func buttons(_ look: Presentation) -> some View {
        VStack(spacing: 9) {
            if let primary = look.primary {
                Button(primary.label) { perform(primary.action) }
                    .buttonStyle(PrimaryButtonStyle(tint: Tone.active.color))
            }
            if let secondary = look.secondary {
                Button(secondary.label) { perform(secondary.action) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(state.preparingShare ? "Preparing…" : "Send to Another Mac…") { perform(.share) }
                .disabled(state.preparingShare)
            separator
            Button("Bluetooth Settings") { perform(.bluetoothSettings) }
            if state.hasKnownController {
                separator
                Button("Forget Controller") { perform(.forget) }
            }
        }
        .buttonStyle(LinkButtonStyle())
    }

    private var separator: some View {
        Circle().fill(Color.secondary.opacity(0.45)).frame(width: 2.5, height: 2.5)
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The live window: ContentView fed by the model, plus the dialogs that need real windows.
struct ContentRoot: View {
    @ObservedObject var model: AppModel
    @State private var confirmingForget = false

    var body: some View {
        ContentView(state: model.viewState) { action in
            if action == .forget {
                confirmingForget = true
            } else {
                model.perform(action)
            }
        }
        .confirmationDialog("Forget this controller?", isPresented: $confirmingForget) {
            Button("Forget Controller", role: .destructive) { model.forgetControllers() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the pairing from this Mac. You can pair it again any time by holding SHARE + PS.")
        }
        .sheet(isPresented: Binding(
            get: { model.shareArchive != nil },
            set: { if !$0 { model.shareArchive = nil } }
        )) {
            if let archive = model.shareArchive {
                ShareSheet(archive: archive) { model.shareArchive = nil }
            }
        }
        .alert("DS4Link", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}

/// Shown once DS4Link.zip is ready: how to get it onto the other Mac and through first launch.
struct ShareSheet: View {
    let archive: URL
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Send DS4Link to another Mac")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text("DS4Link.zip is ready. It contains the app and these steps.")
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .padding(.top, 4)

            Card {
                StepRow(number: 1, text: "Send the zip by AirDrop, or copy it on a USB stick.", tint: Tone.active.color)
                StepRow(number: 2, text: "On the other Mac, open the zip and drag DS4Link into Applications.", tint: Tone.active.color)
                StepRow(number: 3, text: "First launch only: macOS says it can't verify the app. Open System Settings → Privacy & Security and click Open Anyway.", tint: Tone.active.color)
                StepRow(number: 4, text: "Allow Bluetooth, then hold SHARE + PS on the controller.", tint: Tone.active.color)
            }
            .padding(.top, 14)

            HStack(spacing: 9) {
                Button("AirDrop…") { airDrop() }
                    .buttonStyle(PrimaryButtonStyle(tint: Tone.active.color))
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([archive]) }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Done") { done() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(22)
        .frame(width: 430)
    }

    private func airDrop() {
        if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: [archive]) {
            service.perform(withItems: [archive])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([archive])
        }
    }
}
