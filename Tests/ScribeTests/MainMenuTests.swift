import AppKit
import Testing

@testable import Scribe

struct MainMenuTests {
    @Test("Edit menu routes Paste through the focused text responder")
    @MainActor
    func pasteUsesResponderChain() throws {
        let menu = ScribeMainMenu.makeEditMenu()
        let paste = try #require(menu.items.first { $0.title == "Paste" })
        #expect(paste.action == #selector(NSText.paste(_:)))
        #expect(paste.keyEquivalent == "v")
        #expect(paste.keyEquivalentModifierMask == [.command])
        #expect(paste.target == nil)
    }

    @Test("Edit menu includes normal macOS text commands")
    @MainActor
    func standardTextCommandsExist() {
        let menu = ScribeMainMenu.makeEditMenu()
        let actions = Set(menu.items.compactMap(\.action).map(NSStringFromSelector))
        #expect(actions.contains("undo:"))
        #expect(actions.contains("cut:"))
        #expect(actions.contains("copy:"))
        #expect(actions.contains("paste:"))
        #expect(actions.contains("selectAll:"))
    }
}
