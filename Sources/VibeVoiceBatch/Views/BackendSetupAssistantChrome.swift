import AppKit
import SwiftUI
import VibeVoiceBatchCore

struct AssistantStepRail: View {
    let selectedStage: BackendSetupStage
    let highestUnlockedStage: BackendSetupStage
    let selectStage: (BackendSetupStage) -> Void

    private var lockingPolicy: BackendSetupStageLockingPolicy {
        BackendSetupStageLockingPolicy(
            selectedStage: selectedStage,
            highestUnlockedStage: highestUnlockedStage
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Setup Assistant")
                    .font(.title3.weight(.semibold))
                Text("Step \(selectedStage.stepNumber) of \(BackendSetupStage.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            VStack(spacing: 4) {
                ForEach(BackendSetupStage.allCases) { stage in
                    Button {
                        if isUnlocked(stage) {
                            selectStage(stage)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(stepFill(for: stage))
                                    .frame(width: 22, height: 22)
                                Image(systemName: stepSymbol(for: stage))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(stepSymbolTint(for: stage))
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(stage.title)
                                    .lineLimit(1)
                                Text(stepCaption(for: stage))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                            if !isUnlocked(stage) {
                                Image(systemName: "lock.fill")
                                    .imageScale(.small)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedStage == stage ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isUnlocked(stage))
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .background(.regularMaterial)
    }

    private func isUnlocked(_ stage: BackendSetupStage) -> Bool {
        lockingPolicy.isUnlocked(stage)
    }

    private func isCompleted(_ stage: BackendSetupStage) -> Bool {
        lockingPolicy.isCompleted(stage)
    }

    private func stepSymbol(for stage: BackendSetupStage) -> String {
        if isCompleted(stage) {
            return "checkmark"
        }
        if !isUnlocked(stage) {
            return "lock.fill"
        }
        return stage.systemImage
    }

    private func stepFill(for stage: BackendSetupStage) -> Color {
        if selectedStage == stage {
            return .accentColor
        }
        if isCompleted(stage) {
            return .green.opacity(0.2)
        }
        if !isUnlocked(stage) {
            return .secondary.opacity(0.12)
        }
        return .secondary.opacity(0.16)
    }

    private func stepSymbolTint(for stage: BackendSetupStage) -> Color {
        if selectedStage == stage {
            return .white
        }
        if isCompleted(stage) {
            return .green
        }
        return .secondary
    }

    private func stepCaption(for stage: BackendSetupStage) -> String {
        if selectedStage == stage {
            return "Current"
        }
        if isCompleted(stage) {
            return "Completed"
        }
        if isUnlocked(stage) {
            return "Available"
        }
        return "Locked"
    }
}

struct AssistantStatusHeader: View {
    let profile: BackendProfile
    let status: BackendStatusSnapshot
    let report: BackendSetupReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: status.state == .ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(status.state.tint)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Backend Readiness")
                        .font(.headline)
                    Text(nextAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(status.state.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.state.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status.state.tint.opacity(0.12), in: Capsule())
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow {
                    AssistantStatusHeaderValue(title: "Selected Backend", value: profile.displayName)
                    AssistantStatusHeaderValue(title: "Runtime State", value: "\(status.runtime.assistantRuntimeDisplayName) / \(status.state.displayName)")
                }
                GridRow {
                    AssistantStatusHeaderValue(title: "Current Blocking Issue", value: blockingIssue)
                    AssistantStatusHeaderValue(title: "Next Recommended Action", value: nextAction)
                }
            }

            if let details = status.technicalDetails,
               !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("Show Details") {
                    Text(details)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var blockingIssue: String {
        if let failed = report?.blockingChecks.first {
            return "\(failed.title): \(failed.message)"
        }
        if status.state == .ready {
            return "None"
        }
        return status.userMessage
    }

    private var nextAction: String {
        if status.state == .ready {
            return "Continue to model, voice, and test generation."
        }
        if let failed = report?.checks.first(where: { $0.state == .failed }) {
            return failed.recoverySuggestion ?? failed.message
        }
        return status.recoverySuggestion ?? status.userMessage
    }
}

struct AssistantStatusHeaderValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

struct AssistantFooter: View {
    let canGoBack: Bool
    let canContinue: Bool
    let isFinalStage: Bool
    let selectedStage: BackendSetupStage
    let back: () -> Void
    let continueAction: () -> Void

    var body: some View {
        HStack {
            Button("Back", action: back)
                .disabled(!canGoBack)
            Spacer()
            Text("Step \(selectedStage.stepNumber) of \(BackendSetupStage.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(isFinalStage ? "Finish" : "Continue", action: continueAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct SetupTaskPanel<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let state: BackendSetupCheckState?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(state?.tint ?? .secondary)
                    .font(.title3)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if let state {
                    Text(state.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(state.tint.opacity(0.12), in: Capsule())
                }
            }

            content
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SetupCheckInline: View {
    let check: BackendSetupCheck?

    var body: some View {
        if let check {
            VStack(alignment: .leading, spacing: 6) {
                SetupStatusRow(title: check.title, message: check.message, state: check.state)
                if let recovery = check.recoverySuggestion,
                   !recovery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(recovery)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            SetupPlaceholderLine(text: "Run checks to see the current status.")
        }
    }
}

struct SetupStatusRow: View {
    let title: String
    let message: String
    let state: BackendSetupCheckState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: state.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(state.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

struct SetupPlaceholderLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(9)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct SetupDetailGrid: View {
    let items: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                GridRow {
                    Text(item.0)
                        .foregroundStyle(.secondary)
                    Text(item.1.isEmpty ? "Not reported" : item.1)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.caption)
        .padding(.top, 4)
    }
}

struct SetupOperationResult: View {
    let result: BackendOperationResult
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(result.kind.displayName, systemImage: isRunning ? "hourglass" : result.status.assistantSystemImage)
                .foregroundStyle(isRunning ? .secondary : result.status.assistantTint)
            Text(result.message)
                .foregroundStyle(.secondary)
            if let recovery = result.recoverySuggestion {
                Text(recovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct CheckList: View {
    let report: BackendSetupReport?
    let isChecking: Bool

    private var presentation: BackendSetupCheckListPresentation {
        BackendSetupCheckListPresentation(report: report, isChecking: isChecking)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Check Results")
                        .font(.headline)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let report {
                    HStack(spacing: 6) {
                        CheckSummaryBadge(title: "Passed", count: count(.passed, in: report), tint: .green)
                        CheckSummaryBadge(title: "Warnings", count: count(.warning, in: report), tint: .orange)
                        CheckSummaryBadge(title: "Blocking", count: report.blockingChecks.count, tint: .red)
                    }
                }
            }

            Divider()

            switch presentation.state {
            case .checking:
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking backend readiness...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .results:
                if let report {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(report.checks) { check in
                                CheckRow(check: check)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            case .empty:
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No checks yet")
                        .font(.headline)
                    Text("Run checks to see backend readiness, recovery actions, and technical details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: presentation.minimumHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var summaryText: String {
        if isChecking {
            return "Running system checks now."
        }
        guard let report else {
            return "No results yet."
        }
        return "Checked \(report.checks.count) item\(report.checks.count == 1 ? "" : "s") at \(report.generatedAt.formatted(date: .omitted, time: .shortened))."
    }

    private func count(_ state: BackendSetupCheckState, in report: BackendSetupReport) -> Int {
        report.checks.filter { $0.state == state }.count
    }
}

struct CheckRow: View {
    let check: BackendSetupCheck

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: check.state.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(check.state.tint)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(check.title)
                        .font(.headline)
                    Spacer()
                    Text(check.state.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(check.state.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(check.state.tint.opacity(0.12), in: Capsule())
                }

                Text(check.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let recovery = check.recoverySuggestion,
                   !recovery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Label("Recommended", systemImage: "arrow.turn.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(recovery)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Copy Fix") {
                            copy(recovery)
                        }
                        .font(.caption)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                }

                if let details = check.technicalDetails,
                   !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DisclosureGroup("Show Details") {
                        Text(details)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct CheckSummaryBadge: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text("\(count)")
                .monospacedDigit()
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(count == 0 ? .secondary : tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}

struct Header: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

extension BackendSetupCheckState {
    var displayName: String {
        switch self {
        case .waiting: "Waiting"
        case .checking: "Checking"
        case .passed: "Passed"
        case .warning: "Warning"
        case .failed: "Needs Action"
        }
    }

    var systemImage: String {
        switch self {
        case .waiting: "clock"
        case .checking: "arrow.triangle.2.circlepath"
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .waiting, .checking: .secondary
        case .passed: .green
        case .warning: .orange
        case .failed: .red
        }
    }
}

extension BackendSetupReport {
    func check(id: String) -> BackendSetupCheck? {
        checks.first { $0.id == id }
    }
}

extension BackendInstallMethod {
    var assistantInstallMethodDisplayName: String {
        switch self {
        case .managedDockerImage: "Managed Runtime Package"
        case .localPythonEnvironment: "Local Python Environment"
        case .externalServer: "External Server"
        case .bundledNative: "Bundled Native Runtime"
        case .manual: "Manual"
        }
    }
}

extension BackendConnectionKind {
    var assistantDisplayName: String {
        switch self {
        case .managed: "Managed"
        case .installedDockerImage: "Installed Runtime"
        case .externalService: "External Service"
        case .localPython: "Local Python"
        }
    }
}

extension BackendRuntimeState {
    var tint: Color {
        switch self {
        case .ready: .green
        case .runningJob, .installing, .downloadingModel, .starting: .blue
        case .missing, .stopped, .failed: .orange
        case .unknown: .secondary
        }
    }
}

extension BackendRuntime {
    var assistantRuntimeDisplayName: String {
        switch self {
        case .docker: "Managed local runtime"
        case .localPython: "Local Python"
        case .comfyUI: "ComfyUI"
        case .native: "Native"
        case .externalService: "External service"
        }
    }
}

extension BackendDiscoveryConfidence {
    var assistantTint: Color {
        switch self {
        case .high: .green
        case .medium: .blue
        case .low: .secondary
        }
    }
}

extension BackendOperationStatus {
    var assistantSystemImage: String {
        switch self {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .skipped: "minus.circle.fill"
        }
    }

    var assistantTint: Color {
        switch self {
        case .succeeded: .green
        case .failed: .red
        case .skipped: .secondary
        }
    }
}
