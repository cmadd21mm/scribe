import AppKit
import SwiftUI

@MainActor
final class ScribeWindowController: NSWindowController, NSWindowDelegate {
    init(model: ScribeAppModel, demo: Bool) {
        let content = ScribeAppView(model: model)
        let hosting = NSHostingView(rootView: content)
        let size = demo ? NSSize(width: 1_440, height: 1_024) : NSSize(width: 1_260, height: 820)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Scribe"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 1_040, height: 700)
        window.backgroundColor = NSColor(red: 0.988, green: 0.979, blue: 0.955, alpha: 1)
        window.contentView = hosting
        window.center()
        window.setFrameAutosaveName("Scribe.MainWindow")
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
