import Foundation

public enum BackendRuntimeState: String, Codable, Equatable, Sendable {
    case unknown
    case missing
    case stopped
    case installing
    case downloadingModel
    case starting
    case ready
    case runningJob
    case failed

    public var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .missing:
            return "Missing"
        case .stopped:
            return "Stopped"
        case .installing:
            return "Installing"
        case .downloadingModel:
            return "Downloading Model"
        case .starting:
            return "Starting"
        case .ready:
            return "Ready"
        case .runningJob:
            return "Running"
        case .failed:
            return "Failed"
        }
    }

    public var canStartGeneration: Bool {
        self == .ready
    }
}

public struct BackendHealthReport: Codable, Equatable, Sendable {
    public var profileID: String
    public var state: BackendRuntimeState
    public var userMessage: String
    public var recoverySuggestion: String?
    public var technicalDetails: String?

    public init(
        profileID: String,
        state: BackendRuntimeState,
        userMessage: String,
        recoverySuggestion: String? = nil,
        technicalDetails: String? = nil
    ) {
        self.profileID = profileID
        self.state = state
        self.userMessage = userMessage
        self.recoverySuggestion = recoverySuggestion
        self.technicalDetails = technicalDetails
    }
}

public struct BackendStatusSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String { profileID }
    public var profileID: String
    public var displayName: String
    public var runtime: BackendRuntime
    public var state: BackendRuntimeState
    public var checkedAt: Date
    public var userMessage: String
    public var recoverySuggestion: String?
    public var technicalDetails: String?

    public init(
        profileID: String,
        displayName: String,
        runtime: BackendRuntime,
        state: BackendRuntimeState,
        checkedAt: Date,
        userMessage: String,
        recoverySuggestion: String? = nil,
        technicalDetails: String? = nil
    ) {
        self.profileID = profileID
        self.displayName = displayName
        self.runtime = runtime
        self.state = state
        self.checkedAt = checkedAt
        self.userMessage = userMessage
        self.recoverySuggestion = recoverySuggestion
        self.technicalDetails = technicalDetails
    }

    public init(profile: BackendProfile, report: BackendHealthReport, checkedAt: Date = Date()) {
        self.init(
            profileID: profile.id,
            displayName: profile.displayName,
            runtime: profile.runtime,
            state: report.state,
            checkedAt: checkedAt,
            userMessage: report.userMessage,
            recoverySuggestion: report.recoverySuggestion,
            technicalDetails: report.technicalDetails
        )
    }

    public static func unknown(profile: BackendProfile, checkedAt: Date = Date()) -> BackendStatusSnapshot {
        BackendStatusSnapshot(
            profileID: profile.id,
            displayName: profile.displayName,
            runtime: profile.runtime,
            state: .unknown,
            checkedAt: checkedAt,
            userMessage: "Backend status has not been checked yet.",
            recoverySuggestion: "Refresh backend status before generating."
        )
    }

    public var canStartGeneration: Bool {
        state.canStartGeneration
    }

    public func replacingState(
        _ state: BackendRuntimeState,
        userMessage: String,
        recoverySuggestion: String? = nil,
        technicalDetails: String? = nil,
        checkedAt: Date = Date()
    ) -> BackendStatusSnapshot {
        BackendStatusSnapshot(
            profileID: profileID,
            displayName: displayName,
            runtime: runtime,
            state: state,
            checkedAt: checkedAt,
            userMessage: userMessage,
            recoverySuggestion: recoverySuggestion,
            technicalDetails: technicalDetails ?? self.technicalDetails
        )
    }

    public var alertMessage: String {
        [
            "\(displayName): \(state.displayName)",
            userMessage,
            recoverySuggestion
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }
}

public struct DockerRuntimeReport: Codable, Equatable, Sendable {
    public var executablePath: String?
    public var isInstalled: Bool
    public var isRunning: Bool
    public var message: String
    public var details: String?

    public init(
        executablePath: String?,
        isInstalled: Bool,
        isRunning: Bool,
        message: String,
        details: String? = nil
    ) {
        self.executablePath = executablePath
        self.isInstalled = isInstalled
        self.isRunning = isRunning
        self.message = message
        self.details = details
    }
}

public struct BackendProcessResult: Codable, Equatable, Sendable {
    public var exitCode: Int32
    public var combinedOutput: String

    public init(exitCode: Int32, combinedOutput: String) {
        self.exitCode = exitCode
        self.combinedOutput = combinedOutput
    }
}

public final class BackendManager: @unchecked Sendable {
    public typealias DockerExecutableResolver = @Sendable () -> String?
    public typealias ProcessRunner = @Sendable (_ executable: String, _ arguments: [String]) -> BackendProcessResult

    private let projectRoot: URL
    private let fileManager: FileManager
    private let dockerExecutableResolver: DockerExecutableResolver?
    private let processRunner: ProcessRunner?

    public init(
        projectRoot: URL = AppDefaults.projectRoot,
        fileManager: FileManager = .default,
        dockerExecutableResolver: DockerExecutableResolver? = nil,
        processRunner: ProcessRunner? = nil
    ) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
        self.dockerExecutableResolver = dockerExecutableResolver
        self.processRunner = processRunner
    }

    public func registeredProfiles() -> [BackendProfile] {
        BackendProfiles.all
    }

    public func profile(id: String) -> BackendProfile? {
        registeredProfiles().first { $0.id == id }
    }

    public func healthReport(for profile: BackendProfile) -> BackendHealthReport {
        switch profile.runtime {
        case .docker:
            let docker = dockerRuntimeReport()
            if !docker.isInstalled {
                return BackendHealthReport(
                    profileID: profile.id,
                    state: .missing,
                    userMessage: "This backend needs Docker Desktop, but Docker was not found on this Mac.",
                    recoverySuggestion: "Install Docker Desktop, then refresh backend status.",
                    technicalDetails: docker.details
                )
            }
            if !docker.isRunning {
                return BackendHealthReport(
                    profileID: profile.id,
                    state: .stopped,
                    userMessage: "Docker Desktop is installed but is not currently running.",
                    recoverySuggestion: "Start Docker Desktop, then refresh backend status.",
                    technicalDetails: docker.details
                )
            }
            return BackendHealthReport(
                profileID: profile.id,
                state: .ready,
                userMessage: "\(profile.displayName) runtime is available.",
                recoverySuggestion: nil,
                technicalDetails: docker.details
            )
        case .localPython, .comfyUI, .native, .externalService:
            return BackendHealthReport(
                profileID: profile.id,
                state: .unknown,
                userMessage: "Backend checks for \(profile.displayName) have not been implemented yet.",
                recoverySuggestion: "Choose a configured backend before generating."
            )
        }
    }

    public func healthReportAsync(for profile: BackendProfile) async -> BackendHealthReport {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.healthReport(for: profile))
            }
        }
    }

    public func statusSnapshot(for profile: BackendProfile, checkedAt: Date = Date()) -> BackendStatusSnapshot {
        BackendStatusSnapshot(profile: profile, report: healthReport(for: profile), checkedAt: checkedAt)
    }

    public func statusSnapshotAsync(for profile: BackendProfile, checkedAt: Date = Date()) async -> BackendStatusSnapshot {
        let report = await healthReportAsync(for: profile)
        return BackendStatusSnapshot(profile: profile, report: report, checkedAt: checkedAt)
    }

    public func dockerRuntimeReport() -> DockerRuntimeReport {
        guard let docker = resolveDockerExecutable() else {
            return DockerRuntimeReport(
                executablePath: nil,
                isInstalled: false,
                isRunning: false,
                message: "Docker was not found.",
                details: "Checked /usr/local/bin/docker, /opt/homebrew/bin/docker, /usr/bin/docker, and PATH."
            )
        }

        let result = runProcess(executable: docker, arguments: ["info", "--format", "{{.ServerVersion}}"])
        if result.exitCode == 0 {
            return DockerRuntimeReport(
                executablePath: docker,
                isInstalled: true,
                isRunning: true,
                message: "Docker is running.",
                details: result.combinedOutput
            )
        }

        return DockerRuntimeReport(
            executablePath: docker,
            isInstalled: true,
            isRunning: false,
            message: "Docker is installed but not running.",
            details: result.combinedOutput
        )
    }

    public func backendDiskUsageBytes() -> UInt64? {
        guard let enumerator = fileManager.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total: UInt64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else {
                continue
            }
            total += UInt64(size)
        }
        return total
    }

    private func resolveDockerExecutable() -> String? {
        if let dockerExecutableResolver {
            return dockerExecutableResolver()
        }

        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker"
        ]
        if let explicit = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return explicit
        }

        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("docker").path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func runProcess(executable: String, arguments: [String]) -> BackendProcessResult {
        if let processRunner {
            return processRunner(executable, arguments)
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return BackendProcessResult(
                exitCode: process.terminationStatus,
                combinedOutput: String(decoding: data, as: UTF8.self)
            )
        } catch {
            return BackendProcessResult(exitCode: -1, combinedOutput: error.localizedDescription)
        }
    }
}
