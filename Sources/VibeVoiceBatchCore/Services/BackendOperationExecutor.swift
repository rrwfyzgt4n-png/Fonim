import Foundation

private struct DockerRuntimeOperationContext {
    var executablePath: String
    var report: DockerRuntimeReport
}

internal struct BackendOperationExecutor {
    private let projectRoot: URL
    private let dockerRuntimeInspector: BackendDockerRuntimeInspector
    private let processExecutor: BackendProcessExecutor
    private let httpClient: BackendHTTPClient
    private let healthChecker: BackendHealthChecker
    private let fileUtility: BackendRuntimeFileUtility

    init(
        projectRoot: URL,
        dockerRuntimeInspector: BackendDockerRuntimeInspector,
        processExecutor: BackendProcessExecutor,
        httpClient: BackendHTTPClient,
        healthChecker: BackendHealthChecker,
        fileUtility: BackendRuntimeFileUtility
    ) {
        self.projectRoot = projectRoot
        self.dockerRuntimeInspector = dockerRuntimeInspector
        self.processExecutor = processExecutor
        self.httpClient = httpClient
        self.healthChecker = healthChecker
        self.fileUtility = fileUtility
    }

    func perform(_ kind: BackendOperationKind, for profile: BackendProfile) -> BackendOperationResult {
        switch kind {
        case .install:
            return installBackend(profile)
        case .update:
            return updateBackend(profile)
        case .prepare:
            return prepareBackend(profile)
        case .stop:
            return stopBackend(profile)
        case .healthCheck:
            return runHealthCheck(profile)
        case .repair:
            return repairBackend(profile)
        case .reset:
            return resetRuntimeState(profile)
        }
    }

    private func installBackend(_ profile: BackendProfile) -> BackendOperationResult {
        let startedAt = Date()
        guard profile.runtime == .docker,
              profile.installMethod == .managedDockerImage || profile.engineType == .kokoro else {
            return operationResult(
                profile: profile,
                kind: .install,
                status: .skipped,
                startedAt: startedAt,
                message: "Managed install is not available for \(profile.displayName) yet.",
                recoverySuggestion: "Use a backend with a managed local runtime or connect an external backend."
            )
        }
        let directoryLog = fileUtility.ensureProjectDirectoriesLog()
        guard let docker = dockerRuntimeForOperation(profile: profile, kind: .install, startedAt: startedAt) else {
            return missingDockerResult(profile: profile, kind: .install, startedAt: startedAt, directoryLog: directoryLog)
        }
        guard let image = profile.dockerImage else {
            return operationResult(
                profile: profile,
                kind: .install,
                status: .failed,
                startedAt: startedAt,
                message: "\(profile.displayName) does not declare a managed image.",
                technicalDetails: directoryLog
            )
        }

        let pull = processExecutor.run(executable: docker.executablePath, arguments: ["pull", image])
        let ok = pull.exitCode == 0
        return operationResult(
            profile: profile,
            kind: .install,
            status: ok ? .succeeded : .failed,
            startedAt: startedAt,
            message: ok ? "\(profile.displayName) backend image is installed." : "Could not install the backend image.",
            recoverySuggestion: ok ? nil : "Check Docker Desktop, network access, and available disk space, then try again.",
            technicalDetails: [directoryLog, pull.combinedOutput].filter { !$0.isEmpty }.joined(separator: "\n\n")
        )
    }

    private func updateBackend(_ profile: BackendProfile) -> BackendOperationResult {
        let startedAt = Date()
        guard profile.runtime == .docker else {
            return operationResult(
                profile: profile,
                kind: .update,
                status: .skipped,
                startedAt: startedAt,
                message: "Managed update is not available for \(profile.displayName) yet."
            )
        }
        guard let docker = dockerRuntimeForOperation(profile: profile, kind: .update, startedAt: startedAt) else {
            return missingDockerResult(profile: profile, kind: .update, startedAt: startedAt)
        }
        guard let image = profile.dockerImage else {
            return operationResult(
                profile: profile,
                kind: .update,
                status: .failed,
                startedAt: startedAt,
                message: "\(profile.displayName) does not declare a managed image."
            )
        }

        let pull = processExecutor.run(executable: docker.executablePath, arguments: ["pull", image])
        let ok = pull.exitCode == 0
        return operationResult(
            profile: profile,
            kind: .update,
            status: ok ? .succeeded : .failed,
            startedAt: startedAt,
            message: ok ? "\(profile.displayName) backend image is up to date." : "Could not update the backend image.",
            recoverySuggestion: ok ? nil : "Check Docker Desktop and network access, then try again.",
            technicalDetails: pull.combinedOutput
        )
    }

    private func prepareBackend(_ profile: BackendProfile) -> BackendOperationResult {
        let startedAt = Date()
        let directoryLog = fileUtility.ensureProjectDirectoriesLog()
        guard profile.runtime == .docker else {
            return operationResult(
                profile: profile,
                kind: .prepare,
                status: .skipped,
                startedAt: startedAt,
                message: "Prepare is not implemented for \(profile.displayName) yet.",
                technicalDetails: directoryLog
            )
        }
        guard let docker = dockerRuntimeForOperation(profile: profile, kind: .prepare, startedAt: startedAt) else {
            return missingDockerResult(profile: profile, kind: .prepare, startedAt: startedAt, directoryLog: directoryLog)
        }
        if profile.engineType == .kokoro {
            return prepareKokoroDockerBackend(profile, docker: docker, directoryLog: directoryLog, startedAt: startedAt)
        }
        guard let image = profile.dockerImage else {
            return operationResult(
                profile: profile,
                kind: .prepare,
                status: .failed,
                startedAt: startedAt,
                message: "\(profile.displayName) does not declare a managed image.",
                technicalDetails: directoryLog
            )
        }
        let inspect = processExecutor.run(executable: docker.executablePath, arguments: ["image", "inspect", image])
        let ok = inspect.exitCode == 0
        return operationResult(
            profile: profile,
            kind: .prepare,
            status: ok ? .succeeded : .failed,
            startedAt: startedAt,
            message: ok ? "\(profile.displayName) is ready to generate." : "\(profile.displayName) needs its backend image installed first.",
            recoverySuggestion: ok ? nil : "Install the backend image, then prepare again.",
            technicalDetails: [directoryLog, inspect.combinedOutput].filter { !$0.isEmpty }.joined(separator: "\n\n")
        )
    }

    private func stopBackend(_ profile: BackendProfile) -> BackendOperationResult {
        let startedAt = Date()
        guard profile.runtime == .docker else {
            return operationResult(
                profile: profile,
                kind: .stop,
                status: .skipped,
                startedAt: startedAt,
                message: "Stop is not implemented for \(profile.displayName) yet."
            )
        }
        guard let docker = dockerRuntimeForOperation(profile: profile, kind: .stop, startedAt: startedAt, requireRunning: false) else {
            return missingDockerResult(profile: profile, kind: .stop, startedAt: startedAt)
        }
        if profile.engineType == .kokoro {
            return stopKokoroDockerBackend(profile, docker: docker, startedAt: startedAt)
        }

        let list = processExecutor.run(
            executable: docker.executablePath,
            arguments: ["ps", "--filter", "name=vibevoice_batch_", "--format", "{{.Names}}"]
        )
        guard list.exitCode == 0 else {
            return operationResult(
                profile: profile,
                kind: .stop,
                status: .failed,
                startedAt: startedAt,
                message: "Could not inspect running backend containers.",
                recoverySuggestion: "Check Docker Desktop, then try again.",
                technicalDetails: list.combinedOutput
            )
        }

        let names = list.combinedOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if names.isEmpty {
            return operationResult(
                profile: profile,
                kind: .stop,
                status: .succeeded,
                startedAt: startedAt,
                message: "No app-owned backend containers are running.",
                technicalDetails: list.combinedOutput
            )
        }

        let stop = processExecutor.run(executable: docker.executablePath, arguments: ["stop"] + names)
        let ok = stop.exitCode == 0
        return operationResult(
            profile: profile,
            kind: .stop,
            status: ok ? .succeeded : .failed,
            startedAt: startedAt,
            message: ok ? "Stopped \(names.count) app-owned backend container\(names.count == 1 ? "" : "s")." : "Could not stop every app-owned backend container.",
            recoverySuggestion: ok ? nil : "Try cancelling any active generation, then stop the backend again.",
            technicalDetails: [list.combinedOutput, stop.combinedOutput].filter { !$0.isEmpty }.joined(separator: "\n\n")
        )
    }

    private func prepareKokoroDockerBackend(
        _ profile: BackendProfile,
        docker: DockerRuntimeOperationContext,
        directoryLog: String,
        startedAt: Date
    ) -> BackendOperationResult {
        guard let image = backendTrimmedNonEmpty(profile.dockerImage) else {
            return operationResult(
                profile: profile,
                kind: .prepare,
                status: .failed,
                startedAt: startedAt,
                message: "Kokoro needs a Docker image before it can be prepared.",
                recoverySuggestion: "Use discovery or enter the image name in the setup assistant.",
                technicalDetails: directoryLog
            )
        }

        let inspect = processExecutor.run(executable: docker.executablePath, arguments: ["image", "inspect", image])
        guard inspect.exitCode == 0 else {
            return operationResult(
                profile: profile,
                kind: .prepare,
                status: .failed,
                startedAt: startedAt,
                message: "\(image) is not available locally.",
                recoverySuggestion: "Press Install to pull the configured image, then prepare again.",
                technicalDetails: [directoryLog, inspect.combinedOutput].filter { !$0.isEmpty }.joined(separator: "\n\n")
            )
        }

        guard let healthCheckURL = profile.healthCheckURL else {
            return operationResult(
                profile: profile,
                kind: .prepare,
                status: .failed,
                startedAt: startedAt,
                message: "Kokoro needs a local service URL before it can be started.",
                recoverySuggestion: "Enter a service URL such as http://127.0.0.1:8880 in the setup assistant.",
                technicalDetails: [directoryLog, inspect.combinedOutput].filter { !$0.isEmpty }.joined(separator: "\n\n")
            )
        }

        let existingHealth = healthChecker.httpHealthReport(
            profile: profile,
            url: healthCheckURL,
            fallbackDetails: [directoryLog, inspect.combinedOutput].filter { !$0.isEmpty }.joined(separator: "\n\n")
        )
        if existingHealth.state == .ready {
            return operationResult(
                profile: profile,
                kind: .prepare,
                status: .succeeded,
                startedAt: startedAt,
                message: "\(profile.displayName) is already running.",
                technicalDetails: existingHealth.technicalDetails
            )
        }

        let containerName = kokoroContainerName(for: profile)
        let startResult: BackendProcessResult
        let runningContainerList = dockerContainerNames(
            executable: docker.executablePath,
            filter: containerName,
            includeStopped: false
        )
        let containerList = dockerContainerNames(
            executable: docker.executablePath,
            filter: containerName,
            includeStopped: true
        )
        if runningContainerList.contains(containerName) {
            startResult = BackendProcessResult(exitCode: 0, combinedOutput: "\(containerName) is already running.")
        } else if containerList.contains(containerName) {
            startResult = processExecutor.run(executable: docker.executablePath, arguments: ["start", containerName])
        } else {
            guard let hostPort = servicePort(from: healthCheckURL) else {
                return operationResult(
                    profile: profile,
                    kind: .prepare,
                    status: .failed,
                    startedAt: startedAt,
                    message: "Kokoro service URL needs an explicit port.",
                    recoverySuggestion: "Use a service URL such as http://127.0.0.1:8880.",
                    technicalDetails: [directoryLog, inspect.combinedOutput].filter { !$0.isEmpty }.joined(separator: "\n\n")
                )
            }
            startResult = processExecutor.run(
                executable: docker.executablePath,
                arguments: [
                    "run",
                    "-d",
                    "--name",
                    containerName,
                    "-p",
                    "\(hostPort):\(hostPort)",
                    image
                ]
            )
        }

        guard startResult.exitCode == 0 else {
            return operationResult(
                profile: profile,
                kind: .prepare,
                status: .failed,
                startedAt: startedAt,
                message: "Could not start the Kokoro service container.",
                recoverySuggestion: "Check whether the port is already in use or remove the old container, then prepare again.",
                technicalDetails: [directoryLog, inspect.combinedOutput, startResult.combinedOutput].filter { !$0.isEmpty }.joined(separator: "\n\n")
            )
        }

        let ready = healthChecker.waitForHTTPReady(
            profile: profile,
            url: healthCheckURL,
            fallbackDetails: [directoryLog, inspect.combinedOutput, startResult.combinedOutput].filter { !$0.isEmpty }.joined(separator: "\n\n")
        )
        return operationResult(
            profile: profile,
            kind: .prepare,
            status: ready.state == .ready ? .succeeded : .failed,
            startedAt: startedAt,
            message: ready.state == .ready ? "\(profile.displayName) is ready to generate." : "Kokoro started, but did not become ready yet.",
            recoverySuggestion: ready.state == .ready ? nil : "Wait a moment, then run Health Check. If it still fails, inspect the backend logs.",
            technicalDetails: ready.technicalDetails
        )
    }

    private func stopKokoroDockerBackend(
        _ profile: BackendProfile,
        docker: DockerRuntimeOperationContext,
        startedAt: Date
    ) -> BackendOperationResult {
        let configuredName = profile.containerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let appOwnedName = kokoroContainerName(for: profile)
        let candidateNames: [String?] = [configuredName, appOwnedName]
        let namesToInspect = Set<String>(candidateNames.compactMap { name in
            guard let name, !name.isEmpty else { return nil }
            return name
        })

        var runningNames: [String] = []
        var details: [String] = []
        for name in namesToInspect {
            let names = dockerContainerNames(executable: docker.executablePath, filter: name, includeStopped: false)
            runningNames.append(contentsOf: names.filter { $0 == name })
            if !names.isEmpty {
                details.append(names.joined(separator: "\n"))
            }
        }
        runningNames = Array(Set(runningNames)).sorted()

        if runningNames.isEmpty {
            return operationResult(
                profile: profile,
                kind: .stop,
                status: .succeeded,
                startedAt: startedAt,
                message: "No configured Kokoro service container is running.",
                technicalDetails: details.joined(separator: "\n\n")
            )
        }

        let stop = processExecutor.run(executable: docker.executablePath, arguments: ["stop"] + runningNames)
        let ok = stop.exitCode == 0
        return operationResult(
            profile: profile,
            kind: .stop,
            status: ok ? .succeeded : .failed,
            startedAt: startedAt,
            message: ok ? "Stopped Kokoro service." : "Could not stop the Kokoro service.",
            recoverySuggestion: ok ? nil : "Check Docker Desktop, then try again.",
            technicalDetails: (details + [stop.combinedOutput]).filter { !$0.isEmpty }.joined(separator: "\n\n")
        )
    }

    private func runHealthCheck(_ profile: BackendProfile) -> BackendOperationResult {
        let startedAt = Date()
        let report = healthChecker.healthReport(for: profile)
        return operationResult(
            profile: profile,
            kind: .healthCheck,
            status: report.state == .ready ? .succeeded : .failed,
            startedAt: startedAt,
            message: report.userMessage,
            recoverySuggestion: report.recoverySuggestion,
            technicalDetails: report.technicalDetails
        )
    }

    private func repairBackend(_ profile: BackendProfile) -> BackendOperationResult {
        let startedAt = Date()
        let directoryLog = fileUtility.ensureProjectDirectoriesLog()
        if profile.runtime != .docker {
            return operationResult(
                profile: profile,
                kind: .repair,
                status: .skipped,
                startedAt: startedAt,
                message: "Repair is not implemented for \(profile.displayName) yet.",
                technicalDetails: directoryLog
            )
        }
        let prepare = prepareBackend(profile)
        if prepare.status == .succeeded {
            return operationResult(
                profile: profile,
                kind: .repair,
                status: .succeeded,
                startedAt: startedAt,
                message: "\(profile.displayName) repair completed.",
                technicalDetails: [directoryLog, prepare.technicalDetails].compactMap { $0 }.joined(separator: "\n\n")
            )
        }
        let install = installBackend(profile)
        let ok = install.status == .succeeded
        return operationResult(
            profile: profile,
            kind: .repair,
            status: ok ? .succeeded : .failed,
            startedAt: startedAt,
            message: ok ? "\(profile.displayName) repair completed." : "Repair could not make \(profile.displayName) ready.",
            recoverySuggestion: ok ? nil : install.recoverySuggestion,
            technicalDetails: [directoryLog, prepare.technicalDetails, install.technicalDetails].compactMap { $0 }.joined(separator: "\n\n")
        )
    }

    private func resetRuntimeState(_ profile: BackendProfile) -> BackendOperationResult {
        let startedAt = Date()
        let stop = stopBackend(profile)
        let directoryLog = fileUtility.ensureProjectDirectoriesLog()
        let recovered = fileUtility.recoverStrayGeneratedWAV(reason: "backend_reset")
        let details = [
            stop.technicalDetails,
            directoryLog,
            recovered.map { "Recovered staging WAV: \($0.path)" }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        return operationResult(
            profile: profile,
            kind: .reset,
            status: stop.status == .failed ? .failed : .succeeded,
            startedAt: startedAt,
            message: stop.status == .failed ? "Reset could not stop every app-owned backend container." : "Runtime state reset completed without deleting history or model cache.",
            recoverySuggestion: stop.status == .failed ? stop.recoverySuggestion : nil,
            technicalDetails: details
        )
    }

    private func dockerRuntimeForOperation(
        profile: BackendProfile,
        kind: BackendOperationKind,
        startedAt: Date,
        requireRunning: Bool = true
    ) -> DockerRuntimeOperationContext? {
        let docker = dockerRuntimeInspector.report()
        guard docker.isInstalled, let executablePath = docker.executablePath else {
            return nil
        }
        if requireRunning, !docker.isRunning {
            return nil
        }
        return DockerRuntimeOperationContext(executablePath: executablePath, report: docker)
    }

    private func missingDockerResult(
        profile: BackendProfile,
        kind: BackendOperationKind,
        startedAt: Date,
        directoryLog: String? = nil
    ) -> BackendOperationResult {
        let docker = dockerRuntimeInspector.report()
        let message: String
        let suggestion: String
        if !docker.isInstalled {
            message = "Docker Desktop was not found on this Mac."
            suggestion = "Install Docker Desktop, then try \(kind.displayName.lowercased()) again."
        } else {
            message = "Docker Desktop is installed but not running."
            suggestion = "Start Docker Desktop, then try \(kind.displayName.lowercased()) again."
        }
        return operationResult(
            profile: profile,
            kind: kind,
            status: .failed,
            startedAt: startedAt,
            message: message,
            recoverySuggestion: suggestion,
            technicalDetails: [directoryLog, docker.details].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        )
    }

    private func kokoroContainerName(for profile: BackendProfile) -> String {
        if let configured = profile.containerName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return configured
        }
        let suffix = backendStableIdentifier(profile.id).replacingOccurrences(of: "-", with: "_")
        return "vibevoice_batch_\(suffix)"
    }

    private func dockerContainerNames(
        executable: String,
        filter: String,
        includeStopped: Bool
    ) -> [String] {
        var arguments = includeStopped ? ["ps", "-a"] : ["ps"]
        arguments += ["--filter", "name=\(filter)", "--format", "{{.Names}}"]
        let result = processExecutor.run(executable: executable, arguments: arguments)
        guard result.exitCode == 0 else { return [] }
        return result.combinedOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func servicePort(from url: URL) -> Int? {
        url.port
    }

    private func operationResult(
        profile: BackendProfile,
        kind: BackendOperationKind,
        status: BackendOperationStatus,
        startedAt: Date,
        message: String,
        recoverySuggestion: String? = nil,
        technicalDetails: String? = nil
    ) -> BackendOperationResult {
        BackendOperationResult(
            profileID: profile.id,
            kind: kind,
            status: status,
            startedAt: startedAt,
            completedAt: Date(),
            message: message,
            recoverySuggestion: recoverySuggestion,
            technicalDetails: technicalDetails
        )
    }
}
