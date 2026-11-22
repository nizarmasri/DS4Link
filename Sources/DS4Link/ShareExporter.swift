import Foundation

/// Builds DS4Link.zip from the running app so it can be handed to another Mac. The app has no
/// dependencies outside macOS itself, so the copy is complete on its own.
enum ShareExporter {
    enum ExportError: LocalizedError {
        case notAnApp
        case zipFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAnApp: return "DS4Link is not running from an app bundle."
            case .zipFailed(let detail): return "Zipping failed. \(detail)"
            }
        }
    }

    static let installNotes = """
    DS4Link: use a PlayStation controller wirelessly on this Mac
    ============================================================

    INSTALL (once)
      1. Drag DS4Link into your Applications folder.
      2. Open it. The first time, macOS will say it cannot verify the app.
         Click Done, then open System Settings > Privacy & Security,
         scroll down and click "Open Anyway".
         (Terminal alternative:  xattr -dr com.apple.quarantine /Applications/DS4Link.app )
      3. Click Allow when macOS asks to let DS4Link use Bluetooth.

    CONNECT THE CONTROLLER
      1. Make sure the controller is off (light bar dark).
      2. Hold SHARE + PS together for about 3 seconds, until the light bar
         flashes quickly in double blinks.
      3. DS4Link finds it, pairs it and connects it. Nothing to click.

    GOOD TO KNOW
      - A controller remembers only ONE device at a time. After using it with a
        PS4 or another computer, repeat the SHARE + PS step here.
      - Next time on the same Mac, just press the PS button.
      - No cable is needed. If you charge while playing, any Micro-USB cable works.
      - PS5 DualSense: same thing, but hold CREATE + PS.
      - Log file, if something goes wrong: ~/Library/Logs/DS4Link/ds4link.log

    """

    static func makeArchive(from bundle: URL) throws -> URL {
        guard bundle.pathExtension == "app" else { throw ExportError.notAnApp }
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DS4Link-Share-\(UUID().uuidString)", isDirectory: true)
        let stage = root.appendingPathComponent("DS4Link", isDirectory: true)
        try files.createDirectory(at: stage, withIntermediateDirectories: true)
        try files.copyItem(at: bundle, to: stage.appendingPathComponent("DS4Link.app"))
        try Data(installNotes.utf8).write(to: stage.appendingPathComponent("How to install.txt"))

        let archive = root.appendingPathComponent("DS4Link.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", stage.path, archive.path]
        let errors = Pipe()
        ditto.standardError = errors
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ExportError.zipFailed(detail)
        }
        try? files.removeItem(at: stage)
        return archive
    }
}
