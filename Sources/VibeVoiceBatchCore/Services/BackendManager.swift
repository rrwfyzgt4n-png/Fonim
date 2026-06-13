import Foundation

public enum BackendRuntimeState: String, Codable, Equatable {
    case unknown
    case missing
    case stopped
    case installing
    case downloadingModel
    case starting
    case ready
    case runningJob
    case failed
}

public struct BackendHealthReport: Codable, Equatable {
    public var profileID: String
    public var state: BackendRuntimeState
    public var userMessage: String
    public var technicalDetails: String?

    public init(
        profileID: String,
        state: BackendRuntimeState,
        userMessage: String,
        technicalDetails: String? = nil
    ) {
        self.profileID = profileID
        self.state = state
        self.userMessage = userMessage
        self.technicalDetails = technicalDetails
    }
}

public struct DockerRuntimeReport: Codable, Equatable {
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

public final class BackendManager {
    private let projectRoot: URL
    private let fileManager: FileManager

    public init(projectRoot: URL = AppDefaults.projectRoot, fileManager: FileManager = .default) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
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
                    technicalDetails: docker.details
                )
            }
            if !docker.isRunning {
                return BackendHealthReport(
                    profileID: profile.id,
                    state: .stopped,
                    userMessage: "Docker Desktop is installed but is not currently running.",
                    technicalDetails: docker.details
                )
            }
            return BackendHealthReport(
                profileID: profile.id,
                state: .ready,
                userMessage: "\(profile.displayName) runtime is available.",
                technicalDetails: docker.details
            )
        case .localPython, .comfyUI, .native, .externalService:
            return BackendHealthReport(
                profileID: profile.id,
                state: .unknown,
                userMessage: "Backend checks for \(profile.displayName) have not been implemented yet."
            )
        }
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

    private func runProcess(executable: String, arguments: [String]) -> (exitCode: Int32, combinedOutput: String) {
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
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
