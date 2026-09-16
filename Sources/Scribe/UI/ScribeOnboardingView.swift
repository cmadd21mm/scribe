import AppKit
import SwiftUI

struct ScribeOnboardingView: View {
    @ObservedObject var model: ScribeAppModel
    @ObservedObject private var audio: AudioSetupTest
    @State private var name: String
    @State private var showModels = false
    @State private var showAI = false
    private let steps = ["Welcome", "Transcription", "Audio check", "Summaries", "Ready"]

    init(model: ScribeAppModel) {
        self.model = model
        _audio = ObservedObject(wrappedValue: model.audioSetup)
        _name = State(initialValue: model.speakerName)
    }

    private var step: Int { min(4, max(0, model.setupStep)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                ScribeBrand(compact: true)
                Text("Set up Scribe").font(ScribeTheme.serif(23, weight: .semibold))
                Spacer()
                Text("\(step + 1) of 5 · \(steps[step])")
                    .font(ScribeTheme.sans(12)).foregroundStyle(ScribeTheme.mutedInk)
            }
            .padding(26)
            ProgressView(value: Double(step + 1), total: 5)
                .tint(ScribeTheme.coral).accessibilityLabel("Setup step \(step + 1) of 5")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case 0: welcome
                    case 1: transcription
                    case 2: audioCheck
                    case 3: summaries
                    default: ready
                    }
                }
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ScribeSectionDivider()
            HStack {
                if step > 0 {
                    Button("Back") { model.saveSetupStep(step - 1) }
                        .disabled(audio.isBusy)
                }
                Button(audio.isBusy ? "Stop test and finish later" : "Finish later") {
                    if audio.isBusy { audio.discard() }
                    model.completeOnboarding()
                }
                Spacer()
                Button(step == 4 ? (readyToFinish ? "Start using Scribe" : unfinishedAction) : step == 2 && !audio.verified ? "Test later" : "Continue") {
                    guard model.saveSpeakerProfile(name) else { return }
                    if step == 4 && !readyToFinish { model.saveSetupStep(unfinishedStep) }
                    else if step == 4 { model.completeOnboarding() }
                    else { model.saveSetupStep(step + 1) }
                }
                .buttonStyle(ScribePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(audio.isBusy || (step == 1 && model.transcriptionEnabled && !model.transcriptionModel.isInstalled && model.downloadingModelID == nil))
            }
            .padding(24)
        }
        .frame(width: 760, height: 690)
        .background(ScribeTheme.paper)
        .foregroundStyle(ScribeTheme.ink)
        .sheet(isPresented: $showModels) { ScribeModelManagerView(model: model) }
        .sheet(isPresented: $showAI) {
            ScribeAISettingsView(model: model, onClose: { showAI = false })
        }
        .onDisappear { audio.discard() }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Be present. Keep the useful parts.", "Let’s prepare Scribe before your first meeting. You choose when recording starts.")
            setupRow("Your audio stays on this Mac", detail: "Scribe records your microphone and sounds playing on your Mac, including notifications and music.", symbol: "internaldrive")
            setupRow("Searchable transcripts, then optional summaries", detail: "Download a speech model once. Add a separate AI connection only if you want summaries and action items.", symbol: "text.document")
            VStack(alignment: .leading, spacing: 8) {
                Text("What name should appear for you?").font(ScribeTheme.sans(14, weight: .semibold))
                TextField("Your name (optional)", text: $name)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Your speaker name")
                Text("Used for your microphone track in new meetings. You can correct any speaker label later.")
                    .font(ScribeTheme.sans(12)).foregroundStyle(ScribeTheme.mutedInk)
            }
        }
    }

    private var transcription: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("Make your conversations searchable.", "Choose a language model. Downloads need an internet connection; transcription then runs locally.")
            setupRow(model.transcriptionModel.title, detail: model.modelStatusText(), symbol: "cpu")
            if model.downloadingModelID != nil {
                ModelDownloadStatus(model: model)
                Text("You can continue to the audio check while this downloads.")
                    .font(ScribeTheme.sans(12)).foregroundStyle(ScribeTheme.mutedInk)
            } else if !model.transcriptionModel.isInstalled {
                Button("Download \(model.transcriptionModel.title) · \(model.transcriptionModel.approximateSize)") {
                    model.setTranscriptionEnabled(true)
                    model.downloadTranscriptionModel(model.transcriptionModel)
                }.buttonStyle(ScribePrimaryButtonStyle())
            }
            if let error = model.modelDownloadError {
                Text(error).font(ScribeTheme.sans(12)).foregroundStyle(ScribeTheme.coral)
            }
            Button("Choose another language or a smaller model…") { showModels = true }
                .buttonStyle(ScribeSecondaryButtonStyle())
            Toggle("Create transcripts after recording", isOn: Binding(get: { model.transcriptionEnabled }, set: { model.setTranscriptionEnabled($0) }))
            if !model.transcriptionEnabled {
                Text("Audio-only mode: recordings are saved, but transcripts and summaries will wait. You can enable transcription in Settings later.")
                    .font(ScribeTheme.sans(12)).foregroundStyle(ScribeTheme.mutedInk)
            }
        }
    }

    private var audioCheck: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Let’s check your sound together.", "Use your usual headphones or speakers with the volume on. This 15-second check records your voice and plays a short chime.")
            VStack(alignment: .leading, spacing: 12) {
                Text("1. Say a sentence").font(ScribeTheme.sans(14, weight: .semibold))
                Text("We’ll show you a sentence to read aloud and check your microphone.")
                    .font(ScribeTheme.sans(13)).foregroundStyle(ScribeTheme.mutedInk)
                Text("2. Listen for the chime").font(ScribeTheme.sans(14, weight: .semibold))
                Text("Scribe plays it automatically to check Mac audio—the sound from your calls and other apps.")
                    .font(ScribeTheme.sans(13)).foregroundStyle(ScribeTheme.mutedInk)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(ScribeTheme.surface).clipShape(RoundedRectangle(cornerRadius: 9))
            HStack(spacing: 24) {
                signal("Your microphone", detected: audio.microphoneHasSignal)
                signal("Mac audio", detected: audio.systemHasSignal)
            }
            if audio.isRecording {
                Text(AudioSetupGuide.instruction(remainingSeconds: audio.remainingSeconds))
                    .font(ScribeTheme.sans(15, weight: .semibold))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            HStack {
                if audio.isRecording {
                    Button("Stop test · \(audio.remainingSeconds)s") { audio.stop() }
                        .buttonStyle(ScribePrimaryButtonStyle())
                } else {
                    Button(audio.hasRecording ? "Try again" : "Start 15-second check") { audio.start() }
                        .buttonStyle(ScribePrimaryButtonStyle()).disabled(audio.isTranscribing)
                }
                if audio.hasRecording {
                    Button("Hear microphone") { audio.play(track: "mic") }
                    Button("Hear Mac audio") { audio.play(track: "system") }
                }
            }
            if let error = audio.testSoundError { Text(error).font(ScribeTheme.sans(12)).foregroundStyle(ScribeTheme.coral) }
            if let message = audio.message { Text(message).font(ScribeTheme.sans(12)).foregroundStyle(ScribeTheme.mutedInk) }
            if audio.isTranscribing {
                ProgressView("Checking the test transcript…")
            } else if !audio.transcript.isEmpty {
                Text(audio.transcript).font(ScribeTheme.sans(14)).textSelection(.enabled)
                    .padding(14).background(ScribeTheme.surface).clipShape(RoundedRectangle(cornerRadius: 8))
            } else if audio.hasRecording && model.transcriptionModel.isInstalled {
                Button("Transcribe the test") { audio.transcribe() }
            }
            DisclosureGroup("Having trouble with sound?") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("If you didn’t hear the chime, check your sound output and volume. If you heard it but Mac audio was not detected, check Scribe’s system audio access, then try again.")
                    HStack {
                        Button("Sound settings") { model.openSoundSettings() }
                        Button("Microphone access") { model.openPrivacySettings("Privacy_Microphone") }
                        Button("System audio access") { model.openPrivacySettings("Privacy_ScreenCapture") }
                    }
                }.font(ScribeTheme.sans(12)).padding(.top, 8)
            }
            Text("macOS may ask for audio access. Test recordings stay on this Mac and are deleted when you close setup.")
                .font(ScribeTheme.sans(12)).foregroundStyle(ScribeTheme.mutedInk)
        }
    }

    private var summaries: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Add summaries when you’re ready.", "Transcripts work without an AI account. Summaries, decisions, and action items need a separate model.")
            setupRow("Transcripts only", detail: "Continue without connecting AI. You can add summaries later from Settings.", symbol: "text.alignleft")
            setupRow("Optional meeting AI", detail: model.configuredSummaryAIName.map { "Configured: \($0). Use Test connection in AI settings to verify it." } ?? "Connect an installed local model, or choose a provider and your own API key. A chat subscription may not include API access.", symbol: "sparkles")
            Button("Set up optional summaries…") { showAI = true }.buttonStyle(ScribeSecondaryButtonStyle())
            Text("Remote providers receive meeting context only when you request a summary or ask a question. Audio capture and transcription stay local.")
                .font(ScribeTheme.sans(13)).foregroundStyle(ScribeTheme.mutedInk)
        }
    }

    private var readyToFinish: Bool {
        SetupReadiness.canFinish(transcriptionEnabled: model.transcriptionEnabled, modelInstalled: model.transcriptionModel.isInstalled, audioVerified: audio.verified && !audio.microphoneAccessNeedsReview, transcriptionVerified: audio.verifiedTranscriptionModelID == model.transcriptionModel.id)
    }

    private var unfinishedStep: Int {
        model.transcriptionEnabled && !model.transcriptionModel.isInstalled ? 1 : 2
    }

    private var unfinishedAction: String {
        unfinishedStep == 1 ? "Finish model setup" : "Review audio check"
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 20) {
            title(readyToFinish ? "Your essentials are ready." : "Let’s finish the remaining checks.", readyToFinish ? "Scribe never starts recording automatically. Your first meeting is one click away once you’re ready." : "The results below show what still needs attention. Optional summaries do not prevent setup from finishing.")
            setupRow("Recording", detail: audio.microphoneAccessNeedsReview ? audio.verificationDetail + " macOS also reports microphone access is off; review access if the microphone test fails." : audio.verificationDetail, symbol: audio.verified && !audio.microphoneAccessNeedsReview ? "checkmark.circle" : "circle.dashed")
            setupRow("Transcription", detail: model.transcriptionEnabled ? model.modelStatusText() + (audio.verifiedTranscriptionModelID == model.transcriptionModel.id ? " · test passed" : " · test transcript still needed") : "Audio-only mode selected", symbol: "text.document")
            setupRow("Summaries", detail: model.configuredSummaryAIName.map { "Configured: \($0)" } ?? "Optional · not connected", symbol: "sparkles")
            setupRow("Your files", detail: model.root.path, symbol: "folder")
            Text("Calendar naming, launch at login, and call prompts are optional. You can adjust them in Settings.")
                .font(ScribeTheme.sans(13)).foregroundStyle(ScribeTheme.mutedInk)
        }
    }

    private func title(_ heading: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading).font(ScribeTheme.serif(30, weight: .semibold))
            Text(detail).font(ScribeTheme.sans(14)).foregroundStyle(ScribeTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setupRow(_ heading: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 21)).foregroundStyle(ScribeTheme.coral).frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                Text(heading).font(ScribeTheme.sans(14, weight: .semibold))
                Text(detail).font(ScribeTheme.sans(13)).foregroundStyle(ScribeTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(ScribeTheme.surface.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func signal(_ title: String, detected: Bool) -> some View {
        let status = detected ? "sound detected" : audio.isRecording ? "listening…" : audio.hasRecording || audio.verification != nil ? "not detected" : "not checked"
        return Label("\(title): \(status)", systemImage: detected ? "checkmark.circle.fill" : "waveform")
            .font(ScribeTheme.sans(13)).foregroundStyle(detected ? ScribeTheme.ink : ScribeTheme.mutedInk)
    }
}

struct ModelDownloadStatus: View {
    @ObservedObject var model: ScribeAppModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(model.modelDownloadStartedAt ?? context.date))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Downloading model · \(elapsed / 60)m \(elapsed % 60)s")
                    Spacer()
                    Button("Cancel download") { model.onCancelModelDownload?() }
                }
                Text(elapsed > 180 ? "Still working. Download time depends on your connection. If it appears stuck, cancel and retry." : "Downloading and preparing files. This can take several minutes.")
                    .font(ScribeTheme.sans(12)).foregroundStyle(ScribeTheme.mutedInk)
            }
        }
    }
}
