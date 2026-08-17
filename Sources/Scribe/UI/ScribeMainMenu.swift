import AppKit

@MainActor
final class ScribeMainMenu: NSObject {
    var onToggleRecording: (() -> Void)?
    var onOpenFolder: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    func install() {
        let main = NSMenu()

        let appRoot = NSMenuItem()
        let appMenu = NSMenu(title: "Scribe")
        appMenu.addItem(withTitle: "About Scribe", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Scribe", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Scribe", action: #selector(quit), keyEquivalent: "q")
        appRoot.submenu = appMenu
        main.addItem(appRoot)

        let fileRoot = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open Recordings Folder", action: #selector(openFolder), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileRoot.submenu = fileMenu
        main.addItem(fileRoot)

        let recordingRoot = NSMenuItem()
        let recordingMenu = NSMenu(title: "Recording")
        recordingMenu.addItem(withTitle: "Start or Stop Recording", action: #selector(toggleRecording), keyEquivalent: "r")
        recordingRoot.submenu = recordingMenu
        main.addItem(recordingRoot)

        for item in appMenu.items + fileMenu.items + recordingMenu.items where item.action != nil {
            if item.target == nil { item.target = self }
        }
        NSApp.mainMenu = main
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Scribe",
            .applicationVersion: "0.1.0",
            .credits: NSAttributedString(string: "Stay in the conversation.\nFree, open source, and local first."),
        ])
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openFolder() { onOpenFolder?() }
    @objc private func toggleRecording() { onToggleRecording?() }
    @objc private func quit() { onQuit?() }
}
