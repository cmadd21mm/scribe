import AppKit
import Testing

@testable import Scribe

struct MainMenuTests {
    @Test("Opening an already-running Scribe restores its hidden window")
    @MainActor
    func reopenRestoresWindow() throws {
        _ = NSApplication.shared
        let model = ScribeAppModel(root: FileManager.default.temporaryDirectory, demo: true)
        let controller = ScribeWindowController(model: model, demo: true)
        let window = try #require(controller.window)
        window.orderOut(nil)

        #expect(!window.isVisible)
        #expect(controller.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        #expect(window.isVisible)

        window.orderOut(nil)
    }

    @Test("A denied microphone recording opens the correct privacy pane")
    func deniedMicrophonePresentation() {
        let result = RecordingFailureMapper.presentation(
            for: RecordingStartError.permission("Microphone access is required.")
        )
        #expect(result.message == "Microphone access is required.")
        #expect(result.settingsPane == "Privacy_Microphone")
    }

    @Test("Unknown recording failures stay visible without guessing a settings pane")
    func genericRecordingFailurePresentation() {
        let result = RecordingFailureMapper.presentation(for: CocoaError(.fileWriteUnknown))
        #expect(result.message.contains("couldn’t start recording"))
        #expect(result.settingsPane == nil)
    }

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
