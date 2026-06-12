import Foundation

public struct DockerRunResult: Equatable {
    public let exitCode: Int32
    public let wasCancelled: Bool
    public let elapsedSeconds: Double

    public init(exitCode: Int32, wasCancelled: Bool, elapsedSeconds: Double) {
        self.exitCode = exitCode
        self.wasCancelled = wasCancelled
        self.elapsedSeconds = elapsedSeconds
    }
}

public final class DockerGenerationRunner {
    private let stateQueue = DispatchQueue(label: "local.vibevoice.batch.docker-runner")
    private var process: Process?
    private var containerName: String?
    private var cancellationRequested = false

    public init() {}

    public func run(
        command: DockerRunCommand,
        logHandler: @escaping (String) -> Void
    ) throws -> DockerRunResult {
        let startedAt = Date()
        let process = Process()
        let pipe = Pipe()

        let usesScript = FileManager.default.isExecutableFile(atPath: "/usr/bin/script")
        if usesScript {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            process.arguments = ["-q", "/dev/null", command.executable] + command.arguments
        } else if command.executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command.executable] + command.arguments
        }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe

        stateQueue.sync {
            self.process = process
            self.containerName = command.containerName
            self.cancellationRequested = false
        }

        try process.run()

        let reader = pipe.fileHandleForReading
        while true {
            let chunk = try reader.read(upToCount: 4096)
            guard let chunk, !chunk.isEmpty else { break }
            logHandler(String(decoding: chunk, as: UTF8.self))
        }

        process.waitUntilExit()

        let wasCancelled = stateQueue.sync { cancellationRequested }
        stateQueue.sync {
            self.process = nil
            self.containerName = nil
        }

        return DockerRunResult(
            exitCode: process.terminationStatus,
            wasCancelled: wasCancelled,
            elapsedSeconds: Date().timeIntervalSince(startedAt)
        )
    }

    public func cancel() {
        let snapshot = stateQueue.sync { () -> (Process?, String?) in
            cancellationRequested = true
            return (process, containerName)
        }

        if let containerName = snapshot.1 {
            stopContainer(named: containerName)
        }
        snapshot.0?.terminate()
    }

    private func stopContainer(named name: String) {
        let docker = DockerCommandBuilder.make(
            sessionID: "cancel",
            voice: AppDefaults.defaultVoice,
            cfgScale: AppDefaults.defaultCFGScale
        ).executable

        let stopProcess = Process()
        if docker.hasPrefix("/") {
            stopProcess.executableURL = URL(fileURLWithPath: docker)
            stopProcess.arguments = ["stop", name]
        } else {
            stopProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            stopProcess.arguments = [docker, "stop", name]
        }
        stopProcess.standardOutput = Pipe()
        stopProcess.standardError = Pipe()
        try? stopProcess.run()
    }
}
