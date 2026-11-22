import AppKit
import DS4LinkCore

let arguments = CommandLine.arguments

// Developer flags. Without any, this is the normal app.
//   --cli <command>          drive the Bluetooth engine from a terminal (see CLI.swift)
//   --render-preview <dir>   write a PNG of every screen, in light and dark
//   --render-icon <file>     write the 1024px app icon
//   --install-notes          print the install notes that ship inside DS4Link.zip

if let flag = arguments.firstIndex(of: "--render-preview") {
    let dir = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "preview"
    MainActor.assumeIsolated { PreviewRenderer.run(outputDir: dir) }
}

if let flag = arguments.firstIndex(of: "--render-icon") {
    let path = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "icon.png"
    MainActor.assumeIsolated { PreviewRenderer.renderIcon(to: path) }
}

if arguments.contains("--install-notes") {
    print(ShareExporter.installNotes, terminator: "")
    exit(0)
}

if let flag = arguments.firstIndex(of: "--cli") {
    CLI.run(Array(arguments[(flag + 1)...]))
}

DS4LinkApp.main()
