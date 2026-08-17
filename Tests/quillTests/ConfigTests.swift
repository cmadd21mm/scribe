import Foundation
import Testing

@testable import quill

struct ConfigTests {
    @Test("Configuration parses every supported local-first setting")
    func parsesConfiguration() throws {
        let document = try Config.parse(Data(#"""
        {
          "recordings_dir": "~/Meetings",
          "call_apps": ["us.zoom.xos", "example.call"],
          "call_prompt_delay_seconds": 12,
          "call_end_delay_seconds": 20,
          "minimum_free_disk_gb": 3.5,
          "prompt_for_calls": false,
          "mic_voice_processing": true,
          "transcription": {"enabled": true, "engine": "parakeet"},
          "summarization": {
            "backend": "llama.cpp",
            "executable": "/opt/llama-cli",
            "model_path": "/models/local.gguf",
            "prediction_tokens": 900
          }
        }
        """#.utf8))

        #expect(document.recordingsDir == "~/Meetings")
        #expect(document.callApps == ["us.zoom.xos", "example.call"])
        #expect(document.callPromptDelaySeconds == 12)
        #expect(document.callEndDelaySeconds == 20)
        #expect(document.minimumFreeDiskGB == 3.5)
        #expect(document.micVoiceProcessing == true)
        #expect(document.promptForCalls == false)
        #expect(document.transcription?.engine == "parakeet")
        #expect(document.summarization?.backend == "llama.cpp")
        #expect(document.summarization?.modelPath == "/models/local.gguf")
        #expect(document.summarization?.predictionTokens == 900)
    }

    @Test("Unknown keys are forward-compatible")
    func ignoresUnknownKeys() throws {
        let document = try Config.parse(Data(#"{"future_option":true}"#.utf8))
        #expect(document == QuillConfiguration())
    }
}
