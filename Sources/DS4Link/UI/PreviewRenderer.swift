import AppKit
import DS4LinkCore
import SwiftUI

/// Renders every screen from canned data, so the whole UI can be checked without a controller.
enum PreviewRenderer {
    @MainActor
    static func run(outputDir: String) -> Never {
        let dir = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ready = ControllerStatus(name: "DualShock 4", wireless: true, batteryPercent: 72, charging: false, registered: true, hasLight: true)
        let cabled = ControllerStatus(name: "DualShock 4", wireless: false, batteryPercent: 100, charging: true, registered: true, hasLight: true)
        let unregistered = ControllerStatus(name: "DualShock 4", wireless: true, batteryPercent: nil, charging: false, registered: false, hasLight: false)
        let failure = PadFailure(
            title: "Couldn't pair the controller",
            detail: "The controller stopped listening. Switch the controller off (hold PS for 10 seconds), then hold SHARE + PS until the light flashes quickly, and try again."
        )
        let pressing = PadInput(pressed: [.cross, .r2, .left], leftX: -0.8, leftY: 0.5, rightX: 0.3, rightY: -0.9)

        let screens: [(String, ViewState)] = [
            ("01-starting", ViewState(phase: .starting)),
            ("02-searching-new", ViewState(phase: .searching(knownName: nil), secondsLeft: 107, searchElapsed: 13)),
            ("03-searching-known-hint", ViewState(phase: .searching(knownName: "DualShock 4"), secondsLeft: 68, searchElapsed: 52)),
            ("04-pairing", ViewState(phase: .pairing(name: "DualShock 4"), secondsLeft: 90, searchElapsed: 30)),
            ("05-connecting-retry-note", ViewState(phase: .connecting(name: "DualShock 4"), note: "The controller did not answer in time. Trying again…")),
            ("06-connected", ViewState(phase: .connected(ready))),
            ("07-connected-pressing", ViewState(phase: .connected(ready), input: pressing)),
            ("08-connected-settling", ViewState(phase: .connected(unregistered), settling: true)),
            ("09-connected-unregistered", ViewState(phase: .connected(unregistered))),
            ("10-cable", ViewState(phase: .connected(cabled))),
            ("11-idle-known", ViewState(phase: .idle(knownName: "DualShock 4"), note: "Controller switched off. Press PS to wake it.")),
            ("12-idle-none", ViewState(phase: .idle(knownName: nil))),
            ("13-failed", ViewState(phase: .failed(failure))),
            ("14-permission", ViewState(phase: .needsPermission)),
            ("15-bluetooth-off", ViewState(phase: .bluetoothOff)),
        ]

        for (scheme, suffix) in [(ColorScheme.light, "light"), (ColorScheme.dark, "dark")] {
            for (name, state) in screens {
                let view = ContentView(state: state, perform: { _ in })
                    .environment(\.colorScheme, scheme)
                write(view, to: dir.appendingPathComponent("\(name)-\(suffix).png"), scale: 2)
            }
        }
        let sheet = ShareSheet(archive: URL(fileURLWithPath: "/tmp/DS4Link.zip"), done: {})
            .background(Palette.window(.light))
            .environment(\.colorScheme, .light)
        write(sheet, to: dir.appendingPathComponent("16-share-sheet-light.png"), scale: 2)
        print(dir.path)
        exit(0)
    }

    @MainActor
    static func renderIcon(to path: String) -> Never {
        write(AppIconView(), to: URL(fileURLWithPath: path), scale: 1)
        print(path)
        exit(0)
    }

    @MainActor
    private static func write<V: View>(_ view: V, to url: URL, scale: CGFloat) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else {
            FileHandle.standardError.write(Data("could not render \(url.lastPathComponent)\n".utf8))
            return
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}

/// 1024pt macOS icon: the pad in white on a blue squircle.
struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.25, green: 0.56, blue: 1.0), Color(red: 0.07, green: 0.26, blue: 0.86)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
            ControllerArt(
                lightBar: Color(red: 0.55, green: 0.9, blue: 1.0),
                accent: .white,
                style: ControllerArt.Style(
                    body: .white,
                    detail: Color(red: 0.16, green: 0.42, blue: 0.96),
                    recess: Color(red: 0.78, green: 0.87, blue: 1.0)
                )
            )
            .scaleEffect(2.25)
            .offset(y: -6)
        }
        .frame(width: 1024, height: 1024)
    }
}
