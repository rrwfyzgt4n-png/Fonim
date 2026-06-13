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

    public func setupReport(for profile: BackendProfile, generatedAt: Date = Date()) -> BackendSetupReport {
        var checks: [BackendSetupCheck] = []
        checks.append(systemCompatibilityCheck(for: profile))
        checks.append(projectFoldersCheck())

        switch profile.runtime {
        case .docker:
            let docker = dockerRuntimeReport()
            checks.append(dockerSetupCheck(docker))
            checks.append(dockerImageCheck(profile: profile, docker: docker))
            checks.append(modelCacheCheck(profile: profile))
        case .localPython, .comfyUI, .native, .externalService:
            checks.append(
                BackendSetupCheck(
                    id: "runtime-\(profile.id)",
                    title: "Runtime",
                    state: .warning,
                    message: "Setup checks for \(profile.displayName) are not implemented yet.",
                    recoverySuggestion: "Use the VibeVoice backend while additional backend installers are added."
                )
            )
        }

        let health = healthReport(for: profile)
        checks.append(
            BackendSetupCheck(
                id: "health-\(profile.id)",
                title: "Backend health",
                state: health.state == .ready ? .passed : .failed,
                message: health.userMessage,
                recoverySuggestion: health.recoverySuggestion,
                technicalDetails: health.technicalDetails
            )
        )

        return BackendSetupReport(profileID: profile.id, generatedAt: generatedAt, checks: checks)
    }

    public func setupReportAsync(for profile: BackendProfile, generatedAt: Date = Date()) async -> BackendSetupReport {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.setupReport(for: profile, generatedAt: generatedAt))
            }
        }
    }

    private func systemCompatibilityCheck(for profile: BackendProfile) -> BackendSetupCheck {
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let architecture = currentArchitecture
        let supported = profile.supportedArchitectures.contains(.universal) ||
            profile.supportedArchitectures.contains(architecture)
        let memoryRequired = profile.requiredMemoryGB ?? 0
        let memoryOK = memoryRequired == 0 || memoryGB >= memoryRequired
        let state: BackendSetupCheckState = supported && memoryOK ? .passed : .warning

        var details = [
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Architecture: \(architecture.rawValue)",
            String(format: "Memory: %.1f GB", memoryGB)
        ]
        if let required = profile.requiredMemoryGB {
            details.append(String(format: "Required memory: %.1f GB", required))
        }

        return BackendSetupCheck(
            id: "system-\(profile.id)",
            title: "Mac compatibility",
            state: state,
            message: supported && memoryOK ? "This Mac meets the known requirements for \(profile.displayName)." : "This Mac may be below the recommended requirements.",
            recoverySuggestion: state == .passed ? nil : "Generation may still work, but use shorter scripts or a lighter backend if performance is poor.",
            technicalDetails: details.joined(separator: "\n")
        )
    }

    private func projectFoldersCheck() -> BackendSetupCheck {
        let requiredFolders = [
            projectRoot.historyDirectory,
            projectRoot.outputsDirectory,
            projectRoot.recoveredDirectory,
            projectRoot.hfCacheDirectory
        ]
        let missing = requiredFolders.filter { !fileManager.fileExists(atPath: $0.path) }
        return BackendSetupCheck(
            id: "project-folders",
            title: "Local folders",
            state: missing.isEmpty ? .passed : .warning,
            message: missing.isEmpty ? "Project folders are present." : "Some local folders will be created when needed.",
            recoverySuggestion: missing.isEmpty ? nil : "If generation cannot write files, check permissions for \(projectRoot.path).",
            technicalDetails: missing.map(\.path).joined(separator: "\n")
        )
    }

    private func dockerSetupCheck(_ docker: DockerRuntimeReport) -> BackendSetupCheck {
        if !docker.isInstalled {
            return BackendSetupCheck(
                id: "docker-runtime",
                title: "Docker Desktop",
                state: .failed,
                message: "Docker Desktop was not found on this Mac.",
                recoverySuggestion: "Install Docker Desktop, then run setup checks again.",
                technicalDetails: docker.details
            )
        }
        if !docker.isRunning {
            return BackendSetupCheck(
                id: "docker-runtime",
                title: "Docker Desktop",
                state: .failed,
                message: "Docker Desktop is installed but not running.",
                recoverySuggestion: "Start Docker Desktop, then run setup checks again.",
                technicalDetails: docker.details
            )
        }
        return BackendSetupCheck(
            id: "docker-runtime",
            title: "Docker Desktop",
            state: .passed,
            message: "Docker Desktop is installed and running.",
            technicalDetails: docker.details
        )
    }

    private func dockerImageCheck(profile: BackendProfile, docker: DockerRuntimeReport) -> BackendSetupCheck {
        guard docker.isRunning, let dockerExecutable = docker.executablePath else {
            return BackendSetupCheck(
                id: "docker-image-\(profile.id)",
                title: "Backend image",
                state: .waiting,
                message: "Image check waits until Docker Desktop is running."
            )
        }
        guard let image = profile.dockerImage else {
            return BackendSetupCheck(
                id: "docker-image-\(profile.id)",
                title: "Backend image",
                state: .warning,
                message: "This backend does not declare a Docker image."
            )
        }
        let result = runProcess(executable: dockerExecutable, arguments: ["image", "inspect", image])
        return BackendSetupCheck(
            id: "docker-image-\(profile.id)",
            title: "Backend image",
            state: result.exitCode == 0 ? .passed : .warning,
            message: result.exitCode == 0 ? "\(image) is available locally." : "\(image) is not available locally yet.",
            recoverySuggestion: result.exitCode == 0 ? nil : "Phase 5 will add managed pull/update. For now, make sure the working image is available before generation.",
            technicalDetails: result.combinedOutput
        )
    }

    private func modelCacheCheck(profile: BackendProfile) -> BackendSetupCheck {
        let cacheExists = fileManager.fileExists(atPath: projectRoot.hfCacheDirectory.path)
        let hasModelHint = profile.requiredModels.contains { model in
            model.source == AppDefaults.modelPath
        }
        return BackendSetupCheck(
            id: "model-cache-\(profile.id)",
            title: "Model cache",
            state: cacheExists ? .passed : .warning,
            message: cacheExists ? "The local model cache folder is present." : "The local model cache folder has not been created yet.",
            recoverySuggestion: cacheExists ? nil : "The backend can create the cache during its first model download, or you can create the folder during backend install.",
            technicalDetails: hasModelHint ? "Expected model: \(AppDefaults.modelPath)" : nil
        )
    }

    private var currentArchitecture: SystemArchitecture {
        #if arch(arm64)
        return .appleSilicon
        #elseif arch(x86_64)
        return .intel
        #else
        return .universal
        #endif
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
