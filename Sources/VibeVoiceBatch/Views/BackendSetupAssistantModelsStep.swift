import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct ModelsVoicesSetupPane: View {
    let profile: BackendProfile
    let catalogReport: BackendCatalogReport?
    let isLoadingCatalog: Bool
    let modelOptions: [BackendCatalogModel]
    let voiceOptions: [BackendCatalogVoice]
    let defaultModelID: String
    let defaultVoiceID: String
    @Binding var selectedModelID: String
    @Binding var selectedVoiceID: String
    let loadCatalog: () -> Void
    let useAsDefault: (_ modelID: String, _ voiceID: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "Models & Voices", subtitle: "Confirm the model and voice choices before the test generation.")

            ModelVoiceBackendPanel(profile: profile)

            if profile.engineType == .kokoro || profile.engineType == .chatterbox {
                CatalogReadPanel(
                    profile: profile,
                    report: catalogReport,
                    isLoading: isLoadingCatalog,
                    loadCatalog: loadCatalog
                )
            }

            ChoiceSelectionPanel(
                title: "Model",
                subtitle: modelSubtitle,
                systemImage: "cube",
                choices: modelChoices,
                selectedID: $selectedModelID,
                defaultID: defaultModelID,
                emptyMessage: "No model choices are available yet."
            )

            ChoiceSelectionPanel(
                title: "Voice",
                subtitle: voiceSubtitle,
                systemImage: "person.wave.2",
                choices: voiceChoices,
                selectedID: $selectedVoiceID,
                defaultID: defaultVoiceID,
                emptyMessage: "No voice choices are available yet."
            )

            ModelVoiceConfirmationPanel(
                profile: profile,
                model: selectedModelChoice,
                voice: selectedVoiceChoice,
                savedAsDefault: selectedModelID == defaultModelID && selectedVoiceID == defaultVoiceID,
                hasFreshCatalog: catalogReport != nil,
                useAsDefault: {
                    useAsDefault(selectedModelID, selectedVoiceID)
                }
            )
        }
    }

    private var modelChoices: [AssistantCatalogChoice] {
        modelOptions.map { model in
            AssistantCatalogChoice(
                id: model.id,
                displayName: model.displayName,
                detail: model.owner.map { "Owner: \($0)" } ?? "Model ID: \(model.id)"
            )
        }
    }

    private var voiceChoices: [AssistantCatalogChoice] {
        voiceOptions.map { voice in
            AssistantCatalogChoice(
                id: voice.id,
                displayName: voice.displayName,
                detail: "Voice ID: \(voice.id)"
            )
        }
    }

    private var selectedModelChoice: AssistantCatalogChoice? {
        modelChoices.first { $0.id == selectedModelID } ?? modelChoices.first
    }

    private var selectedVoiceChoice: AssistantCatalogChoice? {
        voiceChoices.first { $0.id == selectedVoiceID } ?? voiceChoices.first
    }

    private var modelSubtitle: String {
        if profile.engineType == .kokoro || profile.engineType == .chatterbox {
            return catalogReport == nil ?
                "Use the saved model or read choices from the local service." :
                "Choose from the models discovered on the local service."
        }
        return "The model comes from the selected backend profile."
    }

    private var voiceSubtitle: String {
        if profile.engineType == .kokoro || profile.engineType == .chatterbox {
            return catalogReport == nil ?
                "Use the saved voice or read choices from the local service." :
                "Choose from the voices discovered on the local service."
        }
        return "Choose the default voice used for new generation jobs."
    }
}

struct ModelVoiceBackendPanel: View {
    let profile: BackendProfile

    var body: some View {
        SetupTaskPanel(
            title: "Selected Backend",
            subtitle: "These choices apply to the backend selected earlier in the assistant.",
            systemImage: "server.rack",
            state: .passed
        ) {
            SetupDetailGrid(items: [
                ("Backend", profile.displayName),
                ("Role", profile.role),
                ("Runtime", profile.runtime.assistantRuntimeDisplayName),
                ("Output", profile.outputFormatSupport.map { $0.rawValue.uppercased() }.joined(separator: ", "))
            ])
        }
    }
}

struct CatalogReadPanel: View {
    let profile: BackendProfile
    let report: BackendCatalogReport?
    let isLoading: Bool
    let loadCatalog: () -> Void

    var body: some View {
        SetupTaskPanel(
            title: "Discovered Choices",
            subtitle: "Read the model and voice inventory exposed by the configured local service.",
            systemImage: "list.bullet.rectangle",
            state: catalogState
        ) {
            HStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading model and voice choices...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(report?.message ?? "No catalog has been read yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    loadCatalog()
                } label: {
                    Label(isLoading ? "Reading..." : "Read Choices", systemImage: isLoading ? "hourglass" : "list.bullet.rectangle")
                }
                .disabled(isLoading)
            }

            if let report {
                SetupDetailGrid(items: [
                    ("Models", "\(report.models.count)"),
                    ("Voices", "\(report.voices.count)"),
                    ("Read At", report.generatedAt.formatted(date: .abbreviated, time: .shortened))
                ])

                if report.models.isEmpty && report.voices.isEmpty {
                    SetupPlaceholderLine(text: "No choices were returned. Check the service connection, then read choices again.")
                }

                if let details = report.technicalDetails,
                   !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DisclosureGroup("Catalog Details") {
                        Text(details)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var catalogState: BackendSetupCheckState {
        if isLoading {
            return .checking
        }
        guard let report else {
            return .waiting
        }
        return report.models.isEmpty && report.voices.isEmpty ? .warning : .passed
    }
}

struct AssistantCatalogChoice: Identifiable, Equatable {
    let id: String
    let displayName: String
    let detail: String
}

struct ChoiceSelectionPanel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let choices: [AssistantCatalogChoice]
    @Binding var selectedID: String
    let defaultID: String
    let emptyMessage: String

    private var selectedChoice: AssistantCatalogChoice? {
        choices.first { $0.id == selectedID } ?? choices.first
    }

    var body: some View {
        SetupTaskPanel(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            state: choices.isEmpty ? .warning : .passed
        ) {
            if choices.isEmpty {
                SetupPlaceholderLine(text: emptyMessage)
            } else {
                Picker(title, selection: $selectedID) {
                    ForEach(choices) { choice in
                        Text(menuTitle(for: choice)).tag(choice.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                if let selectedChoice {
                    ChoiceSelectionRow(
                        choice: selectedChoice,
                        isDefault: selectedChoice.id == defaultID
                    )
                }
            }
        }
    }

    private func menuTitle(for choice: AssistantCatalogChoice) -> String {
        choice.id == defaultID ? "\(choice.displayName) (Default)" : choice.displayName
    }
}

struct ChoiceSelectionRow: View {
    let choice: AssistantCatalogChoice
    let isDefault: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(choice.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("Selected")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.14), in: Capsule())
                    if isDefault {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.14), in: Capsule())
                    }
                }

                Text(choice.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ModelVoiceConfirmationPanel: View {
    let profile: BackendProfile
    let model: AssistantCatalogChoice?
    let voice: AssistantCatalogChoice?
    let savedAsDefault: Bool
    let hasFreshCatalog: Bool
    let useAsDefault: () -> Void

    private var canSave: Bool {
        model != nil && voice != nil
    }

    var body: some View {
        SetupTaskPanel(
            title: "Ready for Test Voice",
            subtitle: "The next step will generate a short sample with this backend, model, and voice.",
            systemImage: "waveform",
            state: canSave ? .passed : .warning
        ) {
            SetupDetailGrid(items: [
                ("Backend", profile.displayName),
                ("Model", model?.displayName ?? "Not selected"),
                ("Voice", voice?.displayName ?? "Not selected"),
                ("Default State", savedAsDefault ? "Saved as app default" : "Selected for this setup run")
            ])

            HStack {
                Button("Use as Default", action: useAsDefault)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || (savedAsDefault && !hasFreshCatalog))

                if savedAsDefault {
                    Label("Already saved as the app default", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Continue will use the selected choices for the test; saving also updates future generations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }
}
