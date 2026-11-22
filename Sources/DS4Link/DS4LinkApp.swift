import AppKit
import DS4LinkCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy would fight the first over the same Bluetooth inquiry.
        let me = NSRunningApplication.current
        if let id = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .filter { $0.processIdentifier != me.processIdentifier }
            if let first = others.first {
                first.activate(options: [.activateAllWindows])
                NSApp.terminate(nil)
                return
            }
        }
        AppModel.shared.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct DS4LinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        Window("DS4Link", id: "main") {
            ContentRoot(model: model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button("Search for Controller") { model.beginSearch(userInitiated: true) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Open Bluetooth Settings") { model.openBluetoothSettings() }
                Divider()
                Button("Show Log in Finder") { model.showLog() }
            }
        }
    }
}
