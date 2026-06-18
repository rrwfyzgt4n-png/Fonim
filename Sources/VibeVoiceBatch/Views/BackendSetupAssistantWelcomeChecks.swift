import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct WelcomeSetupPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Local Backend Setup", systemImage: "checkmark.seal")
                .font(.title2.weight(.semibold))

            Text("This assistant checks whether the selected local narration backend is ready before you generate audio.")
                .foregroundStyle(.secondary)
        }
    }
}

struct ChooseBackendSetupPane: View {
    @Binding var selectedBackendID: String
    @Binding var mode: BackendSetupMode
    let statusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: "Choose Backend", subtitle: "Choose how this Mac should run local narration.")

            Form {
                Picker("Backend", selection: $selectedBackendID) {
                    ForEach(BackendProfiles.all) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("Backend mode", selection: $mode) {
                    Text("Simple").tag(BackendSetupMode.simple)
                    Text("Advanced").tag(BackendSetupMode.advanced)
                    Text("External").tag(BackendSetupMode.external)
                }
                .pickerStyle(.radioGroup)

                LabeledContent("Selected mode", value: mode.displayName)
                LabeledContent("Current status", value: statusText)
            }
            .formStyle(.grouped)
        }
    }
}

struct ChecksSetupPane: View {
    let profile: BackendProfile
    let report: BackendSetupReport?
    let isChecking: Bool
    let runChecks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "System Check", subtitle: profile.displayName)

            CheckList(report: report, isChecking: isChecking)

            HStack {
                Button(isChecking ? "Checking..." : "Run Checks", action: runChecks)
                    .disabled(isChecking)
                Spacer()
            }
        }
    }
}

struct ConfirmSetupPane: View {
    let isReady: Bool
    let complete: () -> Void
    let rerunChecks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(
                title: isReady ? "Backend Ready" : "Setup Needs Attention",
                subtitle: isReady ? "The selected backend passed setup checks." : "Run checks again after addressing the blocking items."
            )

            HStack {
                Button("Run Checks Again", action: rerunChecks)
                Spacer()
                Button("Finish", action: complete)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isReady)
            }
        }
    }
}
