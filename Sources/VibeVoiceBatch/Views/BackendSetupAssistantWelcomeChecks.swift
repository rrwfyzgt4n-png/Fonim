import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct WelcomeSetupPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Local Backend Setup", systemImage: "checkmark.seal")
                .font(.title2.weight(.semibold))

            Text("This assistant checks whether the selected local narration backend is ready before you generate audio.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                AssistantWelcomePoint(systemImage: "server.rack", title: "Choose a backend", detail: "Use VibeVoice, Kokoro, or a configured local service.")
                AssistantWelcomePoint(systemImage: "checklist", title: "Check readiness", detail: "Confirm runtime, model, voice, and service state.")
                AssistantWelcomePoint(systemImage: "waveform", title: "Test voice", detail: "Generate a short archived sample before finishing.")
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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

            BackendModeSummary(mode: mode)
        }
    }
}

private struct AssistantWelcomePoint: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BackendModeSummary: View {
    let mode: BackendSetupMode

    var body: some View {
        Label(summary, systemImage: mode == .external ? "network" : "shippingbox")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var summary: String {
        switch mode {
        case .simple:
            return "Simple mode prepares the recommended managed local backend."
        case .advanced:
            return "Advanced mode keeps backend choices visible for manual setup."
        case .external:
            return "External mode connects to a service you already run."
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
