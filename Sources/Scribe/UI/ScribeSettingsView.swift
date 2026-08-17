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
                        settingToggle(
                            "Launch Scribe at login",
                            detail: "Keeps the menu-bar control ready without opening a recording.",
                            isOn: Binding(
                                get: { model.launchAtLogin },
                                set: { value in model.setLaunchAtLogin(value) }
                            )
                        )
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
                            HStack(spacing: 12) {
                                Image(systemName: source.symbol)
                                    .font(.system(size: 17))
                                    .foregroundStyle(ScribeTheme.ink)
                                    .frame(width: 24)
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
                        HStack(spacing: 12) {
                            Image(systemName: "cpu")
                                .foregroundStyle(ScribeTheme.ink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Transcription model")
                                    .font(ScribeTheme.sans(13, weight: .medium))
                                Text(model.modelStatusText())
                                    .font(ScribeTheme.sans(10))
                                    .foregroundStyle(ScribeTheme.faintInk)
                            }
                            Spacer()
                            Button("Download model…") {
                                model.onDownloadTranscriptionModel?()
                            }
                            .buttonStyle(ScribeSecondaryButtonStyle())
                        }
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "text.document")
                                .foregroundStyle(ScribeTheme.ink)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Meeting notes are always ready")
                                    .font(ScribeTheme.sans(13, weight: .medium))
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
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(ScribeTheme.ink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Note style")
                                    .font(ScribeTheme.sans(13, weight: .medium))
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

                    settingsSection("Storage") {
                        HStack(spacing: 12) {
                            Image(systemName: "folder")
                                .foregroundStyle(ScribeTheme.ink)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Recordings folder")
                                    .font(ScribeTheme.sans(13, weight: .medium))
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
                .background(Color.white.opacity(0.48))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(ScribeTheme.divider, lineWidth: 1)
                )
        }
    }

    private func settingToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
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
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(ScribeTheme.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ScribeTheme.sans(13, weight: .medium))
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
        .background(Color.white.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(ScribeTheme.divider, lineWidth: 1)
        )
    }
}
