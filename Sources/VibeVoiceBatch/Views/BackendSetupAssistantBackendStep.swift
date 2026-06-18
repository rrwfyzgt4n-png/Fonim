import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct BackendInstallSetupPane: View {
    let profile: BackendProfile
    let report: BackendSetupReport?
    let discoveryReport: BackendDiscoveryReport?
    let operationResult: BackendOperationResult?
    let isChecking: Bool
    let isDiscovering: Bool
    let isOperationRunning: Bool
    let activeOperation: BackendOperationKind?
    @Binding var connection: BackendConnectionSettings
    let discover: () -> Void
    let applyCandidate: (BackendDiscoveryCandidate) -> Void
    let install: () -> Void
    let repair: () -> Void
    let prepare: () -> Void
    let runChecks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "Install / Connect", subtitle: profile.role)

            RuntimeStatusPanel(
                profile: profile,
                report: report,
                isChecking: isChecking,
                isOperationRunning: isOperationRunning,
                activeOperation: activeOperation,
                prepare: prepare,
                runChecks: runChecks
            )

            BackendAssetsPanel(
                profile: profile,
                report: report,
                isOperationRunning: isOperationRunning,
                activeOperation: activeOperation,
                install: install,
                repair: repair
            )

            ServiceConnectionPanel(
                profile: profile,
                report: report,
                connection: $connection,
                runChecks: runChecks
            )

            BackendDiscoveryPanel(
                profile: profile,
                report: discoveryReport,
                isDiscovering: isDiscovering,
                discover: discover,
                applyCandidate: applyCandidate
            )

            if let operationResult {
                SetupOperationResult(result: operationResult, isRunning: isOperationRunning)
            }
        }
    }
}

struct RuntimeStatusPanel: View {
    let profile: BackendProfile
    let report: BackendSetupReport?
    let isChecking: Bool
    let isOperationRunning: Bool
    let activeOperation: BackendOperationKind?
    let prepare: () -> Void
    let runChecks: () -> Void

    private var check: BackendSetupCheck? {
        report?.check(id: "docker-runtime") ??
            report?.check(id: "runtime-\(profile.id)") ??
            report?.check(id: "health-\(profile.id)")
    }

    var body: some View {
        SetupTaskPanel(
            title: "Runtime Status",
            subtitle: runtimeSummary,
            systemImage: "gearshape.2",
            state: check?.state
        ) {
            if let check {
                SetupCheckInline(check: check)
            } else {
                SetupPlaceholderLine(text: isChecking ? "Checking the local runtime..." : "Run checks to refresh runtime readiness.")
            }

            HStack {
                Button {
                    prepare()
                } label: {
                    Label("Prepare", systemImage: activeOperation == .prepare ? "hourglass" : "play.circle")
                }
                .disabled(isOperationRunning)

                Button(isChecking ? "Checking..." : "Refresh", action: runChecks)
                    .disabled(isOperationRunning || isChecking)

                Spacer()
            }

            DisclosureGroup("Advanced Details") {
                SetupDetailGrid(items: [
                    ("Runtime", profile.runtime.assistantRuntimeDisplayName),
                    ("Install Method", profile.installMethod.assistantInstallMethodDisplayName),
                    ("Container", profile.containerName ?? "Managed when needed"),
                    ("Technical Details", check?.technicalDetails ?? "No runtime log yet")
                ])
            }
            .font(.caption)
        }
    }

    private var runtimeSummary: String {
        switch profile.runtime {
        case .docker:
            return profile.engineType == .vibeVoiceTTS ?
                "The app prepares an isolated local runtime for each generation." :
                "The app can connect to or prepare an isolated local runtime."
        case .externalService:
            return "The app connects to a service you already run."
        case .localPython:
            return "The app uses a local Python environment when configured."
        case .comfyUI:
            return "The app connects to a ComfyUI workflow service."
        case .native:
            return "The app uses a native backend."
        }
    }
}

struct BackendAssetsPanel: View {
    let profile: BackendProfile
    let report: BackendSetupReport?
    let isOperationRunning: Bool
    let activeOperation: BackendOperationKind?
    let install: () -> Void
    let repair: () -> Void

    private var imageCheck: BackendSetupCheck? {
        report?.check(id: "docker-image-\(profile.id)")
    }

    private var modelCheck: BackendSetupCheck? {
        report?.check(id: "model-cache-\(profile.id)")
    }

    var body: some View {
        SetupTaskPanel(
            title: "Backend Assets",
            subtitle: assetSummary,
            systemImage: "shippingbox",
            state: aggregateState
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SetupStatusRow(
                    title: "Runtime Package",
                    message: imageCheck?.message ?? packageMessage,
                    state: imageCheck?.state ?? .waiting
                )
                Divider()
                SetupStatusRow(
                    title: "Model Files",
                    message: modelCheck?.message ?? modelMessage,
                    state: modelCheck?.state ?? .waiting
                )
            }

            HStack {
                Button {
                    install()
                } label: {
                    Label("Install", systemImage: activeOperation == .install ? "hourglass" : "square.and.arrow.down")
                }
                .disabled(isOperationRunning)

                Button {
                    repair()
                } label: {
                    Label("Repair", systemImage: activeOperation == .repair ? "hourglass" : "wrench.and.screwdriver")
                }
                .disabled(isOperationRunning)

                Spacer()
            }

            DisclosureGroup("Advanced Details") {
                SetupDetailGrid(items: [
                    ("Runtime Image", profile.dockerImage ?? "Not required"),
                    ("Required Model", profile.requiredModels.first?.displayName ?? "Not configured"),
                    ("Model Source", profile.requiredModels.first?.source ?? "Not configured"),
                    ("Image Log", imageCheck?.technicalDetails ?? "No image log yet"),
                    ("Model Log", modelCheck?.technicalDetails ?? "No model log yet")
                ])
            }
            .font(.caption)
        }
    }

    private var aggregateState: BackendSetupCheckState? {
        if imageCheck?.state == .failed || modelCheck?.state == .failed {
            return .failed
        }
        if imageCheck?.state == .warning || modelCheck?.state == .warning {
            return .warning
        }
        if imageCheck?.state == .passed || modelCheck?.state == .passed {
            return .passed
        }
        return .waiting
    }

    private var assetSummary: String {
        profile.engineType == .vibeVoiceTTS ?
            "Confirm the narration runtime and required model cache." :
            "Confirm the runtime package and voice model choices."
    }

    private var packageMessage: String {
        profile.dockerImage == nil ? "No managed runtime package is declared for this backend." : "Run checks to confirm the runtime package."
    }

    private var modelMessage: String {
        profile.requiredModels.first.map { "Expected model: \($0.displayName)" } ?? "No required model is declared."
    }
}

struct ServiceConnectionPanel: View {
    let profile: BackendProfile
    let report: BackendSetupReport?
    @Binding var connection: BackendConnectionSettings
    let runChecks: () -> Void

    private var serviceCheck: BackendSetupCheck? {
        report?.check(id: "service-\(profile.id)") ?? report?.check(id: "health-\(profile.id)")
    }

    var body: some View {
        SetupTaskPanel(
            title: "Local Service Connection",
            subtitle: connectionSummary,
            systemImage: "point.3.connected.trianglepath.dotted",
            state: serviceState
        ) {
            if profile.engineType == .vibeVoiceTTS {
                ManagedServiceSummary(profile: profile)
            } else {
                SetupCheckInline(check: serviceCheck)
                KokoroConnectionForm(connection: $connection)
            }

            HStack {
                Button("Refresh Connection", action: runChecks)
                Spacer()
            }
        }
    }

    private var serviceState: BackendSetupCheckState? {
        if profile.engineType == .vibeVoiceTTS {
            return .passed
        }
        return serviceCheck?.state
    }

    private var connectionSummary: String {
        if profile.engineType == .vibeVoiceTTS {
            return "No always-on service is required; generation is staged per job."
        }
        if let serviceURL = connection.trimmedServiceBaseURL {
            return "Connects to \(serviceURL)."
        }
        return "Choose or enter a local service address."
    }
}

struct BackendDiscoveryPanel: View {
    let profile: BackendProfile
    let report: BackendDiscoveryReport?
    let isDiscovering: Bool
    let discover: () -> Void
    let applyCandidate: (BackendDiscoveryCandidate) -> Void

    var body: some View {
        SetupTaskPanel(
            title: "Available Backend Choices",
            subtitle: discoverySummary,
            systemImage: "sparkle.magnifyingglass",
            state: discoveryState
        ) {
            HStack {
                if profile.engineType == .kokoro {
                    Button {
                        discover()
                    } label: {
                        Label(isDiscovering ? "Finding..." : "Find Installed Kokoro", systemImage: isDiscovering ? "hourglass" : "magnifyingglass")
                    }
                    .disabled(isDiscovering)
                }
                Spacer()
            }

            if profile.engineType == .kokoro {
                kokoroDiscoveryContent
            } else {
                ManagedBackendCandidate(profile: profile)
            }
        }
    }

    @ViewBuilder
    private var kokoroDiscoveryContent: some View {
        if isDiscovering {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Looking for installed Kokoro runtimes...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else if let report {
            Text(report.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            if report.candidates.isEmpty {
                SetupPlaceholderLine(text: "No installed Kokoro option was selected automatically. Start your service, then run discovery again, or enter connection details above.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(report.candidates.enumerated()), id: \.element.id) { index, candidate in
                        BackendDiscoveryCandidateRow(
                            candidate: candidate,
                            apply: { applyCandidate(candidate) }
                        )
                        if index < report.candidates.count - 1 {
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }
            }

            if let technicalDetails = report.technicalDetails,
               !technicalDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("Discovery Details") {
                    Text(technicalDetails)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        } else {
            SetupPlaceholderLine(text: "Use discovery if Kokoro is already installed on this Mac.")
        }
    }

    private var discoverySummary: String {
        profile.engineType == .kokoro ?
            "Choose from detected local services or installed runtime packages." :
            "Use the selected managed backend profile."
    }

    private var discoveryState: BackendSetupCheckState? {
        if profile.engineType != .kokoro {
            return .passed
        }
        if isDiscovering {
            return .checking
        }
        guard let report else {
            return .waiting
        }
        return report.candidates.isEmpty ? .warning : .passed
    }
}

struct BackendDiscoveryCandidateRow: View {
    let candidate: BackendDiscoveryCandidate
    let apply: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: candidate.serviceBaseURL == nil ? "shippingbox" : "server.rack")
                .foregroundStyle(candidate.confidence.assistantTint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(candidate.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(candidate.confidence.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(candidate.confidence.assistantTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(candidate.confidence.assistantTint.opacity(0.14), in: Capsule())
                }

                Text(candidateSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !candidate.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(candidate.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Details") {
                    SetupDetailGrid(items: [
                        ("Connection", candidate.connectionKind.assistantDisplayName),
                        ("Service", candidate.serviceBaseURL ?? "Not published to this Mac"),
                        ("Runtime Image", candidate.dockerImage ?? "Not reported"),
                        ("Container", candidate.containerName ?? "Not reported"),
                        ("Model", candidate.modelID),
                        ("Default Voice", candidate.defaultVoice),
                        ("Technical Details", candidate.technicalDetails ?? "No discovery log")
                    ])
                }
                .font(.caption)
            }

            Spacer()

            Button("Use", action: apply)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 10)
    }

    private var candidateSummary: String {
        if candidate.serviceBaseURL != nil {
            return "Ready to connect as a local service."
        }
        if candidate.dockerImage != nil {
            return "Installed runtime package found; service address can be confirmed later."
        }
        return "Possible local backend option."
    }
}

struct ManagedBackendCandidate: View {
    let profile: BackendProfile

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(profile.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("Selected")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.14), in: Capsule())
                }

                Text("Managed local narration backend. The app stages text, runs generation, archives logs and audio, then cleans up staging files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Advanced Details") {
                    SetupDetailGrid(items: [
                        ("Runtime", profile.runtime.assistantRuntimeDisplayName),
                        ("Runtime Image", profile.dockerImage ?? "Not required"),
                        ("Model", profile.requiredModels.first?.displayName ?? "Not configured"),
                        ("Parser", profile.progressParser)
                    ])
                }
                .font(.caption)
            }

            Spacer()
        }
        .padding(.vertical, 10)
    }
}

struct ManagedServiceSummary: View {
    let profile: BackendProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No server setup is required for this backend.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("When you generate audio, the app creates a protected session, stages the text, runs the backend, captures logs, and moves the final WAV into history.")
                .font(.caption)
                .foregroundStyle(.secondary)

            DisclosureGroup("Advanced Details") {
                SetupDetailGrid(items: [
                    ("Backend", profile.displayName),
                    ("Runtime", profile.runtime.assistantRuntimeDisplayName),
                    ("Runtime Image", profile.dockerImage ?? "Not required"),
                    ("Required Model", profile.requiredModels.first?.source ?? "Not configured"),
                    ("Service Endpoint", "Not used")
                ])
            }
            .font(.caption)
        }
    }
}

struct KokoroConnectionForm: View {
    @Binding var connection: BackendConnectionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Connection", selection: binding(\.connectionKind)) {
                ForEach(BackendConnectionKind.allCases, id: \.self) { kind in
                    Text(kind.assistantDisplayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            SetupDetailGrid(items: [
                ("Connection", connection.connectionKind.assistantDisplayName),
                ("Service", connection.trimmedServiceBaseURL ?? "Not set"),
                ("Model", connection.trimmedModelID ?? "Not set"),
                ("Voice", connection.trimmedDefaultVoice ?? "Not set")
            ])

            DisclosureGroup("Edit Connection Details") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    if connection.connectionKind == .installedDockerImage {
                        GridRow {
                            Text("Image").foregroundStyle(.secondary)
                            TextField("kokoro image name", text: binding(\.dockerImage))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Container").foregroundStyle(.secondary)
                            TextField("optional container name", text: optionalBinding(\.containerName))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if connection.connectionKind == .installedDockerImage ||
                        connection.connectionKind == .externalService {
                        GridRow {
                            Text("Service URL").foregroundStyle(.secondary)
                            TextField("http://127.0.0.1:PORT", text: binding(\.serviceBaseURL))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Health").foregroundStyle(.secondary)
                            TextField("/health", text: binding(\.healthPath))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Generate").foregroundStyle(.secondary)
                            TextField("/v1/audio/speech", text: binding(\.generatePath))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    GridRow {
                        Text("Model").foregroundStyle(.secondary)
                        TextField("kokoro/default", text: binding(\.modelID))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Voice").foregroundStyle(.secondary)
                        TextField("default voice", text: binding(\.defaultVoice))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Notes").foregroundStyle(.secondary)
                        TextField("launch command, port, or anything useful", text: binding(\.notes))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .font(.caption)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<BackendConnectionSettings, Value>) -> Binding<Value> {
        Binding(
            get: { connection[keyPath: keyPath] },
            set: { connection[keyPath: keyPath] = $0 }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<BackendConnectionSettings, String?>) -> Binding<String> {
        Binding(
            get: { connection[keyPath: keyPath] ?? "" },
            set: { connection[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }
}
