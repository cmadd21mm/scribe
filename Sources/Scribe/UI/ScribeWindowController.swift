import AppKit
import SwiftUI

@MainActor
final class ScribeWindowController: NSWindowController, NSWindowDelegate, NSApplicationDelegate {
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
        window.backgroundColor = .windowBackgroundColor
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
        let wasInBackground = Self.showInDock()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if wasInBackground {
            // AppKit can leave the main menu unresponsive when an app
            // activates in the same turn it leaves accessory mode.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NSApp.activate(ignoringOtherApps: true) }
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Restores the Dock icon and Cmd-Tab entry. Returns true when Scribe was
    /// running menu-bar-only.
    @discardableResult
    static func showInDock() -> Bool {
        guard NSApp.activationPolicy() != .regular else { return false }
        NSApp.setActivationPolicy(.regular)
        return true
    }

    /// Drops back to menu-bar-only while the main window is closed.
    func hideFromDockIfClosed() {
        guard window?.isVisible != true else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag { present() }
        return true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        present()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        hideFromDockIfClosed()
        return false
    }
}
