import AppKit

@MainActor
final class ScribeMainMenu: NSObject {
    var onToggleRecording: (() -> Void)?
    var onOpenFolder: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onQuit: (() -> Void)?

    func install() {
        let main = NSMenu()

        let appRoot = NSMenuItem()
        let appMenu = NSMenu(title: "Scribe")
        addOwnedItem(to: appMenu, title: "About Scribe", action: #selector(showAbout))
        addOwnedItem(to: appMenu, title: "Check for Updates…", action: #selector(checkForUpdates))
        appMenu.addItem(.separator())
        addOwnedItem(to: appMenu, title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Scribe", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        addOwnedItem(to: appMenu, title: "Quit Scribe", action: #selector(quit), keyEquivalent: "q")
        appRoot.submenu = appMenu
        main.addItem(appRoot)

        let fileRoot = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        addOwnedItem(to: fileMenu, title: "Open Recordings Folder", action: #selector(openFolder), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileRoot.submenu = fileMenu
        main.addItem(fileRoot)

        let editRoot = NSMenuItem()
        editRoot.submenu = Self.makeEditMenu()
        main.addItem(editRoot)

        let recordingRoot = NSMenuItem()
        let recordingMenu = NSMenu(title: "Recording")
        addOwnedItem(to: recordingMenu, title: "Start or Stop Recording", action: #selector(toggleRecording), keyEquivalent: "r")
        recordingRoot.submenu = recordingMenu
        main.addItem(recordingRoot)

        NSApp.mainMenu = main
    }

    static func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pasteAndMatch = menu.addItem(
            withTitle: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v"
        )
        pasteAndMatch.keyEquivalentModifierMask = [.command, .option, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private func addOwnedItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Scribe",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
            .credits: NSAttributedString(string: "Stay in the conversation.\nFree, open source, and local first."),
        ])
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func checkForUpdates() { onCheckForUpdates?() }
    @objc private func openFolder() { onOpenFolder?() }
    @objc private func toggleRecording() { onToggleRecording?() }
    @objc private func quit() { onQuit?() }
}
