import SwiftUI

struct ScribeSettingsView: View {
    @ObservedObject var model: ScribeAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings")
                        .font(ScribeTheme.serif(29, weight: .semibold))
                        .foregroundStyle(ScribeTheme.ink)
                    Text("Private by default. Explicit by design.")
                        .font(ScribeTheme.sans(12))
                        .foregroundStyle(ScribeTheme.mutedInk)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .scribePointer()
            }
            .padding(24)

            ScribeSectionDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    settingsSection("General") {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "circle.lefthalf.filled")
                                .foregroundStyle(ScribeTheme.ink)
                                .frame(width: 28, height: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Appearance")
                                    .font(ScribeTheme.sans(13, weight: .medium))
                                    .foregroundStyle(ScribeTheme.ink)
                                Text("Follow this Mac or keep Scribe in your preferred theme.")
                                    .font(ScribeTheme.sans(10))
                                    .foregroundStyle(ScribeTheme.faintInk)
                            }
                            Spacer()
                            Picker("Appearance", selection: Binding(
                                get: { model.appearance },
                                set: { model.setAppearance($0) }
                            )) {
                                ForEach(ScribeAppearance.allCases) { appearance in
                                    Text(appearance.title).tag(appearance)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 190)
                            .scribePointer()
                        }
                        settingToggle(
                            "Launch Scribe at login",
                            detail: "Keeps the menu-bar control ready without opening a recording.",
                            isOn: Binding(
                                get: { model.launchAtLogin },
                                set: { value in model.setLaunchAtLogin(value) }
                            )
                        )
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(ScribeTheme.ink)
                                .frame(width: 28, height: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Software updates")
                                    .font(ScribeTheme.sans(13, weight: .medium))
                                    .foregroundStyle(ScribeTheme.ink)
                                Text("Install signed, notarized releases over your current copy. Scribe does not force updates.")
                                    .font(ScribeTheme.sans(10))
                                    .foregroundStyle(ScribeTheme.faintInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button("Check now…") {
                                model.showSettings = false
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    model.onCheckForUpdates?()
                                }
                            }
                                .buttonStyle(ScribeSecondaryButtonStyle())
                        }
                    }

                    settingsSection("Recording") {
                        settingToggle(
                            "Offer to record detected calls",
                            detail: "Scribe can notice a supported call and ask. It never starts recording on its own.",
                            isOn: Binding(
                                get: { model.promptForCalls },
                                set: { value in model.setPromptForCalls(value) }
                            )
                        )
                        settingToggle(
                            "Voice processing for speakers",
                            detail: "Useful when remote audio may echo into your microphone.",
                            isOn: Binding(
                                get: { model.voiceProcessingEnabled },
                                set: { value in model.setVoiceProcessingEnabled(value) }
                            )
                        )
                    }

                    settingsSection("Call sources") {
                        ForEach(ScribeAppModel.captureSources) { source in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: source.symbol)
                                    .font(.system(size: 17))
                                    .foregroundStyle(ScribeTheme.ink)
                                    .frame(width: 28, height: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name)
                                        .font(ScribeTheme.sans(13, weight: .medium))
                                        .foregroundStyle(ScribeTheme.ink)
                                    Text(source.detail)
                                        .font(ScribeTheme.sans(10))
                                        .foregroundStyle(ScribeTheme.faintInk)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { model.isSourceEnabled(source) },
                                    set: { model.setSource(source, enabled: $0) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(ScribeTheme.coral)
                                .scribePointer()
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    settingsSection("Local processing") {
                        settingToggle(
                            "Transcribe after recording",
                            detail: "Speech recognition runs on this Mac with a downloaded local model.",
                            isOn: Binding(
                                get: { model.transcriptionEnabled },
                                set: { value in model.setTranscriptionEnabled(value) }
                            )
                        )
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "cpu")
                                .foregroundStyle(ScribeTheme.ink)
                                .frame(width: 28, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Transcription model")
                                    .font(ScribeTheme.sans(13, weight: .medium))
                                    .foregroundStyle(ScribeTheme.ink)
                                Text(model.modelStatusText())
                                    .font(ScribeTheme.sans(10))
                                    .foregroundStyle(ScribeTheme.faintInk)
                            }
                            Spacer()
                            Button("Manage models…") {
                                model.showModelManager = true
                            }
                            .buttonStyle(ScribeSecondaryButtonStyle())
                        }
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "text.document")
                                .foregroundStyle(ScribeTheme.ink)
                                .frame(width: 28, height: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Meeting notes are always ready")
                                    .font(ScribeTheme.sans(13, weight: .medium))
                                    .foregroundStyle(ScribeTheme.ink)
                                Text("Scribe creates private summaries, decisions, action items, and questions without an account or model setup. A configured local llama.cpp model automatically improves the result.")
                                    .font(ScribeTheme.sans(10))
                                    .foregroundStyle(ScribeTheme.faintInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ScribeTheme.coral)
                                .accessibilityLabel("Ready")
                        }
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(ScribeTheme.ink)
                                .frame(width: 28, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Note style")
                                    .font(ScribeTheme.sans(13, weight: .medium))
                                    .foregroundStyle(ScribeTheme.ink)
                                Text("Choose the shape of future meeting summaries.")
                                    .font(ScribeTheme.sans(10))
                                    .foregroundStyle(ScribeTheme.faintInk)
                            }
                            Spacer()
                            Picker("Note style", selection: Binding(
                                get: { model.noteStyle },
                                set: { model.setNoteStyle($0) }
                            )) {
                                ForEach(MeetingNoteStyle.allCases, id: \.self) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                            .scribePointer()
                        }
                    }

                    settingsSection("Meeting intelligence") {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(ScribeTheme.ink)
                                .frame(width: 28, height: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Ask Scribe")
                                    .font(ScribeTheme.sans(13, weight: .medium))
                                    .foregroundStyle(ScribeTheme.ink)
                                Text(model.aiSettings.provider == .local
                                     ? "On-device search with timestamp citations. No account or upload."
                                     : "Connected to \(model.aiSettings.provider.title). Context is shared only when you ask a question.")
                                    .font(ScribeTheme.sans(10))
                                    .foregroundStyle(ScribeTheme.faintInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button("Configure…") { model.showAISettings = true }
                                .buttonStyle(ScribeSecondaryButtonStyle())
                        }
                    }

                    settingsSection("Storage") {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "folder")
                                .foregroundStyle(ScribeTheme.ink)
                                .frame(width: 28, height: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Recordings folder")
                                    .font(ScribeTheme.sans(13, weight: .medium))
                                    .foregroundStyle(ScribeTheme.ink)
                                Text(model.root.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(ScribeTheme.faintInk)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button("Choose…") { model.onChooseRecordingsFolder?() }
                                .buttonStyle(ScribeSecondaryButtonStyle())
                        }
                    }

                    settingsSection("Permissions") {
                        permissionRow(
                            title: "Microphone",
                            detail: "Captures your side of a conversation.",
                            pane: "Privacy_Microphone"
                        )
                        permissionRow(
                            title: "Screen & System Audio",
                            detail: "Captures the other side from the chosen call app.",
                            pane: "Privacy_ScreenCapture"
                        )
                        permissionRow(
                            title: "Calendars",
                            detail: "Optional: names notes from the current event.",
                            pane: "Privacy_Calendars"
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scribe is free and open source.")
                            .font(ScribeTheme.serif(16, weight: .semibold))
                            .foregroundStyle(ScribeTheme.ink)
                        Text("No account, telemetry, meeting bot, cloud transcript, or background upload. Your folder is the source of truth.")
                            .font(ScribeTheme.sans(11))
                            .foregroundStyle(ScribeTheme.mutedInk)
                            .lineSpacing(3)
                    }
                    .padding(.bottom, 10)
                }
                .padding(26)
            }
        }
        .frame(width: 680, height: 760)
        .background(ScribeTheme.paper)
        .sheet(isPresented: $model.showModelManager) {
            ScribeModelManagerView(model: model)
        }
        .sheet(isPresented: $model.showAISettings) {
            ScribeAISettingsView(model: model)
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(ScribeTheme.sans(10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(ScribeTheme.coral)
            VStack(spacing: 12) { content() }
                .padding(16)
                .background(ScribeTheme.surface.opacity(0.68))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(ScribeTheme.divider, lineWidth: 1)
                )
        }
    }

    private func settingToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Color.clear
                .frame(width: 28, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ScribeTheme.sans(13, weight: .medium))
                    .foregroundStyle(ScribeTheme.ink)
                Text(detail)
                    .font(ScribeTheme.sans(10))
                    .foregroundStyle(ScribeTheme.faintInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(ScribeTheme.coral)
                .scribePointer()
        }
    }

    private func permissionRow(title: String, detail: String, pane: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(ScribeTheme.ink)
                .frame(width: 28, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ScribeTheme.sans(13, weight: .medium))
                    .foregroundStyle(ScribeTheme.ink)
                Text(detail)
                    .font(ScribeTheme.sans(10))
                    .foregroundStyle(ScribeTheme.faintInk)
            }
            Spacer()
            Button("Open Settings") { model.openPrivacySettings(pane) }
                .buttonStyle(ScribeSecondaryButtonStyle())
        }
    }
}

struct ScribeModelManagerView: View {
    @ObservedObject var model: ScribeAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcription models")
                        .font(ScribeTheme.serif(28, weight: .semibold))
                        .foregroundStyle(ScribeTheme.ink)
                    Text("Download once, then transcribe entirely on this Mac.")
                        .font(ScribeTheme.sans(12))
                        .foregroundStyle(ScribeTheme.mutedInk)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .scribePointer()
            }
            .padding(24)

            ScribeSectionDivider()

            VStack(spacing: 12) {
                ForEach(LocalTranscriptionModel.allCases) { item in
                    modelCard(item)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(ScribeTheme.coral)
                        .frame(width: 20)
                    Text("Models come from FluidInference on Hugging Face. After download, audio and transcripts remain local. Scribe never downloads a model without your click.")
                        .font(ScribeTheme.sans(10))
                        .foregroundStyle(ScribeTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(width: 610, height: 490)
        .background(ScribeTheme.paper)
    }

    private func modelCard(_ item: LocalTranscriptionModel) -> some View {
        let installed = item.isInstalled
        let selected = model.transcriptionModel == item
        let downloading = model.downloadingModelID == item.id
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: item == .compact ? "hare" : item == .multilingual ? "globe" : "text.badge.checkmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(selected ? ScribeTheme.coral : ScribeTheme.ink)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.title)
                        .font(ScribeTheme.sans(13, weight: .semibold))
                        .foregroundStyle(ScribeTheme.ink)
                    if item == .english {
                        Text("RECOMMENDED")
                            .font(ScribeTheme.sans(8, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(ScribeTheme.coral)
                    }
                }
                Text("\(item.detail) · \(item.approximateSize)")
                    .font(ScribeTheme.sans(10))
                    .foregroundStyle(ScribeTheme.faintInk)
            }
            Spacer()
            if downloading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Downloading \(item.title)")
            } else if selected && installed {
                Label("Selected", systemImage: "checkmark.circle.fill")
                    .font(ScribeTheme.sans(11, weight: .medium))
                    .foregroundStyle(ScribeTheme.coral)
            } else if installed {
                Button("Use") { model.selectTranscriptionModel(item) }
                    .buttonStyle(ScribeSecondaryButtonStyle())
            } else {
                Button("Download") { model.downloadTranscriptionModel(item) }
                    .buttonStyle(ScribeSecondaryButtonStyle())
                    .disabled(model.downloadingModelID != nil)
            }
        }
        .padding(15)
        .frame(minHeight: 78)
        .background(selected ? ScribeTheme.selection.opacity(0.62) : ScribeTheme.surface.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(selected ? ScribeTheme.coral.opacity(0.55) : ScribeTheme.divider, lineWidth: 1)
        )
    }
}

struct ScribeAISettingsView: View {
    @ObservedObject var model: ScribeAppModel
    @Environment(\.dismiss) private var dismiss
    private let onClose: (() -> Void)?
    @State private var provider: ScribeAIProvider
    @State private var modelName: String
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var redactSensitive: Bool
    @State private var availableModels: [ScribeAIModelOption] = []
    @State private var modelSearch = ""
    @State private var isLoadingModels = false
    @State private var modelLoadError: String?
    @State private var usesManualModelEntry = false
    @State private var modelRequestID = UUID()
    @State private var modelLoadTask: Task<Void, Never>?
    @State private var keySaveMessage: String?

    init(model: ScribeAppModel, onClose: (() -> Void)? = nil) {
        self.model = model
        self.onClose = onClose
        let current = model.aiSettings
        _provider = State(initialValue: current.provider)
        let starterModels = current.provider == .venice
            ? ScribeAIModelCatalog.veniceFallbackModels
            : []
        _modelName = State(initialValue: current.model.isEmpty
            ? (starterModels.first?.id ?? "")
            : current.model)
        _baseURL = State(initialValue: current.baseURL)
        _apiKey = State(initialValue: ScribeKeychain.apiKey(provider: current.provider))
        _redactSensitive = State(initialValue: current.redactSensitive)
        _availableModels = State(initialValue: starterModels)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meeting intelligence")
                        .font(ScribeTheme.serif(28, weight: .semibold))
                        .foregroundStyle(ScribeTheme.ink)
                    Text("Choose how Scribe answers questions about your meetings.")
                        .font(ScribeTheme.sans(12))
                        .foregroundStyle(ScribeTheme.mutedInk)
                }
                Spacer()
                Button("Cancel") { close() }
                    .keyboardShortcut(.cancelAction)
                    .scribePointer()
            }
            .padding(24)

            ScribeSectionDivider()

            VStack(alignment: .leading, spacing: 18) {
                fieldLabel("Provider")
                Picker("Provider", selection: $provider) {
                    ForEach(ScribeAIProvider.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: provider) { _, value in
                    baseURL = value.defaultBaseURL
                    apiKey = ScribeKeychain.apiKey(provider: value)
                    availableModels = value == .venice
                        ? ScribeAIModelCatalog.veniceFallbackModels
                        : []
                    modelName = availableModels.first?.id ?? ""
                    modelSearch = ""
                    modelLoadError = nil
                    usesManualModelEntry = false
                    modelRequestID = UUID()
                    modelLoadTask?.cancel()
                    modelLoadTask = nil
                    isLoadingModels = false
                    keySaveMessage = nil
                }

                if provider == .local {
                    Label(
                        "Scribe searches your local transcripts and returns the most relevant timestamped moments. It works offline and sends nothing anywhere.",
                        systemImage: "internaldrive"
                    )
                    .font(ScribeTheme.sans(11))
                    .foregroundStyle(ScribeTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel(provider.needsAPIKey ? "API key" : "API key (optional)")
                        HStack(spacing: 9) {
                            SecureField("Stored in your Mac Keychain", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: apiKey) { _, _ in
                                    availableModels = []
                                    modelSearch = ""
                                    modelLoadError = nil
                                    keySaveMessage = nil
                                    modelRequestID = UUID()
                                    modelLoadTask?.cancel()
                                    modelLoadTask = nil
                                    isLoadingModels = false
                                }
                            Button("Save key") { saveKey() }
                                .buttonStyle(ScribeSecondaryButtonStyle())
                                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let keySaveMessage {
                            Label(keySaveMessage, systemImage: "checkmark.shield")
                                .font(ScribeTheme.sans(9))
                                .foregroundStyle(ScribeTheme.mutedInk)
                        }
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel("API address")
                        TextField("Provider API address", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .disabled(provider != .custom)
                            .onChange(of: baseURL) { _, _ in
                                guard provider == .custom else { return }
                                availableModels = []
                                modelSearch = ""
                                modelLoadError = nil
                                modelRequestID = UUID()
                                modelLoadTask?.cancel()
                                modelLoadTask = nil
                                isLoadingModels = false
                            }
                    }

                    modelPicker

                    Toggle("Redact email addresses and phone numbers before sending context", isOn: $redactSensitive)
                        .toggleStyle(.checkbox)
                        .font(ScribeTheme.sans(11))
                        .foregroundStyle(ScribeTheme.ink)
                        .scribePointer()

                    Label(
                        "Your ChatGPT, Claude, Grok, or Venice subscription may not include API use. Scribe stores the key in Keychain and sends meeting context only after you press Ask.",
                        systemImage: "hand.raised"
                    )
                    .font(ScribeTheme.sans(10))
                    .foregroundStyle(ScribeTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text(provider == .local ? "No setup required." : "You stay in control of each request.")
                        .font(ScribeTheme.sans(10))
                        .foregroundStyle(ScribeTheme.faintInk)
                    Spacer()
                    Button("Save") {
                        let saved = model.saveAISettings(
                            ScribeAISettings(
                                provider: provider,
                                model: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
                                baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                redactSensitive: redactSensitive
                            ),
                            apiKey: apiKey
                        )
                        if saved { onClose?() }
                    }
                    .buttonStyle(ScribePrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .frame(width: 640, height: provider == .local ? 390 : 690)
        .background(ScribeTheme.paper)
        .onDisappear { cancelModelLoad() }
    }

    @ViewBuilder
    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                fieldLabel("Model")
                Spacer()
                if !availableModels.isEmpty {
                    Button("Refresh") { loadModels() }
                        .buttonStyle(.plain)
                        .font(ScribeTheme.sans(10, weight: .medium))
                        .foregroundStyle(ScribeTheme.coral)
                        .disabled(isLoadingModels)
                        .scribePointer()
                }
            }

            if isLoadingModels {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading models available to this account…")
                        .font(ScribeTheme.sans(11))
                        .foregroundStyle(ScribeTheme.mutedInk)
                    Spacer()
                    Button("Cancel") { cancelModelLoad() }
                        .buttonStyle(.plain)
                        .font(ScribeTheme.sans(10, weight: .medium))
                        .foregroundStyle(ScribeTheme.coral)
                        .scribePointer()
                }
                .frame(height: 32)
            } else if !availableModels.isEmpty && !usesManualModelEntry {
                if availableModels.count > 8 {
                    TextField("Search \(availableModels.count) available models", text: $modelSearch)
                        .textFieldStyle(.roundedBorder)
                }

                if filteredModels.isEmpty {
                    Text("No models match “\(modelSearch)”. Clear the search to see every available model.")
                        .font(ScribeTheme.sans(10))
                        .foregroundStyle(ScribeTheme.mutedInk)
                }

                Menu {
                    ForEach(filteredModels) { option in
                        Button {
                            modelName = option.id
                        } label: {
                            if option.id == modelName {
                                Label(optionMenuTitle(option), systemImage: "checkmark")
                            } else {
                                Text(optionMenuTitle(option))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedModel?.title ?? "Choose a model")
                                .font(ScribeTheme.sans(12, weight: .medium))
                                .foregroundStyle(ScribeTheme.ink)
                            if let selectedModel {
                                Text(selectedModel.detail)
                                    .font(ScribeTheme.sans(9))
                                    .foregroundStyle(ScribeTheme.mutedInk)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ScribeTheme.faintInk)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .background(ScribeTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(ScribeTheme.divider, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .disabled(filteredModels.isEmpty)
                .scribePointer()

                Button("Enter a model ID manually") {
                    usesManualModelEntry = true
                    modelSearch = ""
                }
                .buttonStyle(.plain)
                .font(ScribeTheme.sans(10))
                .foregroundStyle(ScribeTheme.mutedInk)
                .scribePointer()
            } else if usesManualModelEntry {
                TextField("Model ID", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Use this for a private or provider-specific model not returned by the API.")
                        .font(ScribeTheme.sans(9))
                        .foregroundStyle(ScribeTheme.mutedInk)
                    Spacer()
                    Button("Use model list") {
                        usesManualModelEntry = false
                    }
                    .buttonStyle(.plain)
                    .font(ScribeTheme.sans(10, weight: .medium))
                    .foregroundStyle(ScribeTheme.coral)
                    .disabled(availableModels.isEmpty)
                    .scribePointer()
                }
            } else {
                HStack(spacing: 10) {
                    Button("Load available models") { loadModels() }
                        .buttonStyle(ScribeSecondaryButtonStyle())
                        .disabled(provider.needsAPIKey && provider != .venice && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text(provider.needsAPIKey && provider != .venice && apiKey.isEmpty
                         ? "Enter your API key first."
                         : provider == .venice
                            ? "Venice publishes this list without exposing your saved key."
                            : "Scribe will ask \(provider.title) which models this account can use.")
                        .font(ScribeTheme.sans(10))
                        .foregroundStyle(ScribeTheme.mutedInk)
                }

                Button("Enter a model ID manually") {
                    usesManualModelEntry = true
                }
                .buttonStyle(.plain)
                .font(ScribeTheme.sans(10))
                .foregroundStyle(ScribeTheme.mutedInk)
                .scribePointer()
            }

            if let modelLoadError {
                Label(modelLoadError, systemImage: "exclamationmark.triangle")
                    .font(ScribeTheme.sans(10))
                    .foregroundStyle(ScribeTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var filteredModels: [ScribeAIModelOption] {
        let query = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableModels }
        return availableModels.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
                || $0.detail.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedModel: ScribeAIModelOption? {
        availableModels.first { $0.id == modelName }
    }

    private func optionMenuTitle(_ option: ScribeAIModelOption) -> String {
        option.title + (option.isRecommended ? " — Recommended" : "")
    }

    private func loadModels() {
        modelLoadTask?.cancel()
        let requestID = UUID()
        modelRequestID = requestID
        let requestedProvider = provider
        let requestedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoadingModels = true
        modelLoadError = nil
        modelLoadTask = Task {
            do {
                let options = try await ScribeAIModelCatalog.fetch(
                    provider: requestedProvider,
                    baseURL: requestedBaseURL,
                    apiKey: requestedAPIKey
                )
                guard modelRequestID == requestID else { return }
                availableModels = options
                if !options.contains(where: { $0.id == modelName }) {
                    modelName = ScribeAIModelCatalog.preferredModel(
                        from: options,
                        provider: requestedProvider
                    )?.id ?? ""
                }
                usesManualModelEntry = false
            } catch {
                guard modelRequestID == requestID else { return }
                guard !Task.isCancelled else { return }
                if requestedProvider == .venice {
                    availableModels = ScribeAIModelCatalog.veniceFallbackModels
                    if modelName.isEmpty {
                        modelName = ScribeAIModelCatalog.veniceFallbackModels.first?.id ?? ""
                    }
                    modelLoadError = "Venice’s live catalog did not respond. Showing a small verified fallback list; Refresh will retry."
                } else {
                    availableModels = []
                    modelLoadError = error.localizedDescription
                }
            }
            guard modelRequestID == requestID else { return }
            isLoadingModels = false
            modelLoadTask = nil
        }
    }

    private func cancelModelLoad() {
        modelRequestID = UUID()
        modelLoadTask?.cancel()
        modelLoadTask = nil
        isLoadingModels = false
    }

    private func saveKey() {
        do {
            try ScribeKeychain.saveAPIKey(
                apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                provider: provider
            )
            keySaveMessage = "Saved securely in Keychain."
        } catch {
            keySaveMessage = nil
            model.alertMessage = "Scribe couldn’t save this API key: \(error.localizedDescription)"
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func fieldLabel(_ value: String) -> some View {
        Text(value.uppercased())
            .font(ScribeTheme.sans(9, weight: .bold))
            .tracking(1)
            .foregroundStyle(ScribeTheme.coral)
    }
}

struct ScribeOnboardingView: View {
    @ObservedObject var model: ScribeAppModel

    var body: some View {
        VStack(spacing: 24) {
            ScribeBrand()
            Text("Be present. Keep the useful parts.")
                .font(ScribeTheme.serif(34, weight: .semibold))
                .foregroundStyle(ScribeTheme.ink)
                .multilineTextAlignment(.center)
            Text("Scribe captures both sides of a conversation only when you choose Record, then turns it into searchable notes on your Mac.")
                .font(ScribeTheme.sans(14))
                .foregroundStyle(ScribeTheme.mutedInk)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 520)

            HStack(alignment: .top, spacing: 14) {
                onboardingCard(
                    symbol: "hand.raised",
                    title: "You decide",
                    detail: "Scribe can offer to record a call. It never records automatically."
                )
                onboardingCard(
                    symbol: "waveform.and.mic",
                    title: "Both sides",
                    detail: "Separate microphone and call-app tracks keep conversations clear."
                )
                onboardingCard(
                    symbol: "internaldrive",
                    title: "Local first",
                    detail: "Audio, transcripts, and Markdown notes stay in a folder you own."
                )
            }

            VStack(spacing: 10) {
                Button("Start using Scribe") {
                    model.completeOnboarding()
                }
                .buttonStyle(ScribePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                Text("macOS will ask for microphone and system-audio access when you make your first recording.")
                    .font(ScribeTheme.sans(10))
                    .foregroundStyle(ScribeTheme.faintInk)
            }
        }
        .padding(38)
        .frame(width: 760, height: 570)
        .background(ScribeTheme.paper)
    }

    private func onboardingCard(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(ScribeTheme.coral)
            Text(title)
                .font(ScribeTheme.serif(17, weight: .semibold))
                .foregroundStyle(ScribeTheme.ink)
            Text(detail)
                .font(ScribeTheme.sans(11))
                .foregroundStyle(ScribeTheme.mutedInk)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, minHeight: 125, alignment: .topLeading)
        .padding(16)
        .background(ScribeTheme.surface.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(ScribeTheme.divider, lineWidth: 1)
        )
    }
}
