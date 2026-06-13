import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        TabView {
            BackendsSettingsPane()
                .tabItem {
                    Label("Backends", systemImage: "server.rack")
                }

            ModelsSettingsPane()
                .tabItem {
                    Label("Models", systemImage: "cube.transparent")
                }

            VoicesSettingsPane()
                .tabItem {
                    Label("Voices", systemImage: "waveform")
                }

            OutputSettingsPane()
                .tabItem {
                    Label("Output", systemImage: "folder")
                }

            AdvancedSettingsPane()
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
        }
        .padding(20)
        .frame(width: 620, height: 420)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply to Editor") {
                    appStore.applyDefaultGenerationSettings()
                }
            }

            ToolbarItem(placement: .cancellationAction) {
                Button("Reset Defaults") {
                    settingsStore.resetDefaults()
                    appStore.applyDefaultGenerationSettings()
                }
            }
        }
    }
}

private struct BackendsSettingsPane: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        Form {
            Picker("Default backend", selection: binding(\.defaultBackendID)) {
                ForEach(BackendProfiles.all) { profile in
                    Text(profile.displayName).tag(profile.id)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Runtime", value: selectedBackend.runtime.displayName)
            LabeledContent("Role", value: selectedBackend.role)
            LabeledContent("Status", value: appStore.backendStatus.state.displayName)

            HStack {
                Button("Refresh Status") {
                    appStore.refreshBackendStatus()
                }

                Button("Show Details") {
                    appStore.showBackendDetails()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var selectedBackend: BackendProfile {
        BackendProfiles.all.first { $0.id == settingsStore.settings.defaultBackendID } ?? BackendProfiles.vibeVoiceTTS
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in settingsStore.update { $0[keyPath: keyPath] = value } }
        )
    }
}

private struct ModelsSettingsPane: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Picker("Default model", selection: binding(\.defaultModelID)) {
                ForEach(BackendProfiles.vibeVoiceTTS.requiredModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Model path", value: settingsStore.settings.defaultModelID)
            LabeledContent("Docker image", value: BackendProfiles.vibeVoiceTTS.dockerImage ?? "Managed by backend")
            LabeledContent("Format support", value: BackendProfiles.vibeVoiceTTS.outputFormatSupport.map(\.displayName).joined(separator: ", "))
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in settingsStore.update { $0[keyPath: keyPath] = value } }
        )
    }
}

private struct VoicesSettingsPane: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Picker("Default voice", selection: binding(\.defaultVoice)) {
                ForEach(AppDefaults.availableVoices, id: \.self) { voice in
                    Text(voice).tag(voice)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Available voices", value: "\(AppDefaults.availableVoices.count)")
            LabeledContent("Current default", value: settingsStore.settings.defaultVoice)
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in settingsStore.update { $0[keyPath: keyPath] = value } }
        )
    }
}

private struct OutputSettingsPane: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Picker("Export format", selection: binding(\.exportFormat)) {
                ForEach(BackendProfiles.vibeVoiceTTS.outputFormatSupport, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.menu)

            HStack {
                TextField("Output folder", text: binding(\.outputFolderPath))
                Button("Choose...") {
                    chooseOutputFolder()
                }
            }

            LabeledContent("History folder", value: AppDefaults.projectRoot.historyDirectory.path)
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in settingsStore.update { $0[keyPath: keyPath] = value } }
        )
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: settingsStore.settings.outputFolderPath, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            settingsStore.update { $0.outputFolderPath = url.path }
        }
    }
}

private struct AdvancedSettingsPane: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Picker("Default CFG scale", selection: binding(\.defaultCFGScale)) {
                ForEach(AppDefaults.availableCFGScales, id: \.self) { cfg in
                    Text(cfg).tag(cfg)
                }
            }
            .pickerStyle(.menu)

            Picker("Default DDPM steps", selection: binding(\.defaultDDPMInferenceSteps)) {
                ForEach(AppDefaults.availableDDPMInferenceSteps, id: \.self) { steps in
                    Text("\(steps)").tag(steps)
                }
            }
            .pickerStyle(.menu)

            Toggle("Show advanced controls in editor", isOn: binding(\.showAdvancedGenerationControls))
            Toggle("Refresh backend status on launch", isOn: binding(\.refreshBackendStatusOnLaunch))
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in settingsStore.update { $0[keyPath: keyPath] = value } }
        )
    }
}

private extension BackendRuntime {
    var displayName: String {
        switch self {
        case .docker: "Managed local runtime"
        case .localPython: "Local Python"
        case .comfyUI: "ComfyUI"
        case .native: "Native"
        case .externalService: "External service"
        }
    }
}

private extension AudioOutputFormat {
    var displayName: String {
        rawValue.uppercased()
    }
}
