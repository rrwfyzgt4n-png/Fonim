import Foundation

public typealias BackendDockerExecutableResolver = @Sendable () -> String?
public typealias BackendProcessRunner = @Sendable (_ executable: String, _ arguments: [String]) -> BackendProcessResult
public typealias BackendHTTPRunner = @Sendable (_ url: URL) -> BackendHTTPResult?

internal struct BackendProcessExecutor {
    private let fileManager: FileManager
    private let dockerExecutableResolver: BackendDockerExecutableResolver?
    private let processRunner: BackendProcessRunner?

    init(
        fileManager: FileManager = .default,
        dockerExecutableResolver: BackendDockerExecutableResolver? = nil,
        processRunner: BackendProcessRunner? = nil
    ) {
        self.fileManager = fileManager
        self.dockerExecutableResolver = dockerExecutableResolver
        self.processRunner = processRunner
    }

    func resolveDockerExecutable() -> String? {
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

    func run(executable: String, arguments: [String]) -> BackendProcessResult {
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

internal struct BackendDockerRuntimeInspector {
    private let processExecutor: BackendProcessExecutor

    init(processExecutor: BackendProcessExecutor) {
        self.processExecutor = processExecutor
    }

    func report() -> DockerRuntimeReport {
        guard let docker = processExecutor.resolveDockerExecutable() else {
            return DockerRuntimeReport(
                executablePath: nil,
                isInstalled: false,
                isRunning: false,
                message: "Docker was not found.",
                details: "Checked /usr/local/bin/docker, /opt/homebrew/bin/docker, /usr/bin/docker, and PATH."
            )
        }

        let result = processExecutor.run(executable: docker, arguments: ["info", "--format", "{{.ServerVersion}}"])
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
}

internal struct BackendHTTPClient {
    private let httpRunner: BackendHTTPRunner?

    init(httpRunner: BackendHTTPRunner? = nil) {
        self.httpRunner = httpRunner
    }

    func get(url: URL, timeout: TimeInterval = 5) -> BackendHTTPResult {
        if let override = httpRunner?(url) {
            return override
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let semaphore = DispatchSemaphore(value: 0)
        var statusCode: Int?
        var body = ""
        var errorDescription: String?

        URLSession.shared.dataTask(with: request) { data, response, error in
            errorDescription = error?.localizedDescription
            statusCode = (response as? HTTPURLResponse)?.statusCode
            if let data {
                body = String(decoding: data.prefix(100_000), as: UTF8.self)
            }
            semaphore.signal()
        }
        .resume()

        let timedOut = semaphore.wait(timeout: .now() + timeout + 1) == .timedOut
        return BackendHTTPResult(
            statusCode: statusCode,
            body: body,
            errorDescription: errorDescription,
            timedOut: timedOut
        )
    }

    func isSuccessful(_ response: BackendHTTPResult) -> Bool {
        guard !response.timedOut, response.errorDescription == nil, let statusCode = response.statusCode else {
            return false
        }
        return (200..<300).contains(statusCode)
    }

    func details(_ response: BackendHTTPResult) -> String {
        var lines: [String] = []
        if response.timedOut {
            lines.append("Timed out")
        }
        if let statusCode = response.statusCode {
            lines.append("HTTP status: \(statusCode)")
        }
        if let errorDescription = response.errorDescription {
            lines.append(errorDescription)
        }
        if !response.body.isEmpty {
            lines.append(response.body)
        }
        return lines.joined(separator: "\n")
    }
}

internal struct BackendDiskUsageAnalyzer {
    private let projectRoot: URL
    private let fileManager: FileManager

    init(projectRoot: URL, fileManager: FileManager = .default) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
    }

    func backendDiskUsageBytes() -> UInt64? {
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

    func report() -> BackendDiskUsageReport {
        BackendDiskUsageReport(
            projectRootBytes: directorySizeBytes(projectRoot),
            historyBytes: directorySizeBytes(projectRoot.historyDirectory),
            outputsBytes: directorySizeBytes(projectRoot.outputsDirectory),
            recoveredBytes: directorySizeBytes(projectRoot.recoveredDirectory),
            modelCacheBytes: directorySizeBytes(projectRoot.hfCacheDirectory)
        )
    }

    func directorySizeBytes(_ url: URL) -> UInt64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: UInt64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else {
                continue
            }
            total += UInt64(size)
        }
        return total
    }
}

internal struct BackendRuntimeFileUtility {
    private let projectRoot: URL
    private let fileManager: FileManager

    init(projectRoot: URL, fileManager: FileManager = .default) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
    }

    func ensureProjectDirectoriesLog() -> String {
        let folders = [
            projectRoot.historyDirectory,
            projectRoot.outputsDirectory,
            projectRoot.recoveredDirectory,
            projectRoot.hfCacheDirectory,
            projectRoot.dockerOverridesDirectory
        ]
        var lines: [String] = []
        for folder in folders {
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                lines.append("Ready: \(folder.path)")
            } catch {
                lines.append("Could not prepare \(folder.path): \(error.localizedDescription)")
            }
        }
        return lines.joined(separator: "\n")
    }

    func recoverStrayGeneratedWAV(reason: String) -> URL? {
        let generated = projectRoot.generatedWAVFile
        guard fileManager.fileExists(atPath: generated.path) else { return nil }
        do {
            try fileManager.createDirectory(at: projectRoot.recoveredDirectory, withIntermediateDirectories: true)
            let destination = projectRoot.recoveredDirectory
                .appendingPathComponent("\(timestampForRecoveredFile())_\(reason)_input_generated.wav")
            let finalDestination = uniqueURL(destination)
            try fileManager.moveItem(at: generated, to: finalDestination)
            return finalDestination
        } catch {
            return nil
        }
    }

    func uniqueURL(_ url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 2
        while true {
            let candidate = directory.appendingPathComponent("\(base)_\(counter)").appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    private func timestampForRecoveredFile() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }
}

internal var backendCurrentArchitecture: SystemArchitecture {
    #if arch(arm64)
    return .appleSilicon
    #elseif arch(x86_64)
    return .intel
    #else
    return .universal
    #endif
}

internal func backendStableIdentifier(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics
    return value.unicodeScalars.map { scalar in
        allowed.contains(scalar) ? String(scalar).lowercased() : "-"
    }
    .joined()
    .split(separator: "-")
    .joined(separator: "-")
}

internal func backendTrimmedNonEmpty(_ value: String?) -> String? {
    value?.trimmedOrNil
}
