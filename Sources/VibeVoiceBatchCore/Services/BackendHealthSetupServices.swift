import Foundation

internal struct BackendHealthChecker {
    private let dockerRuntimeInspector: BackendDockerRuntimeInspector
    private let processExecutor: BackendProcessExecutor
    private let httpClient: BackendHTTPClient

    init(
        dockerRuntimeInspector: BackendDockerRuntimeInspector,
        processExecutor: BackendProcessExecutor,
        httpClient: BackendHTTPClient
    ) {
        self.dockerRuntimeInspector = dockerRuntimeInspector
        self.processExecutor = processExecutor
        self.httpClient = httpClient
    }

    func healthReport(for profile: BackendProfile) -> BackendHealthReport {
        switch profile.runtime {
        case .docker:
            let docker = dockerRuntimeInspector.report()
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
            if profile.engineType == .kokoro {
                return kokoroDockerHealthReport(profile: profile, docker: docker)
            }
            return BackendHealthReport(
                profileID: profile.id,
                state: .ready,
                userMessage: "\(profile.displayName) runtime is available.",
                recoverySuggestion: nil,
                technicalDetails: docker.details
            )
        case .externalService:
            return externalServiceHealthReport(profile: profile)
        case .localPython, .comfyUI, .native:
            return configuredRuntimeHealthReport(profile: profile)
        }
    }

    func httpHealthReport(
        profile: BackendProfile,
        url: URL,
        fallbackDetails: String? = nil
    ) -> BackendHealthReport {
        let response = httpClient.get(url: url)

        if response.timedOut {
            return BackendHealthReport(
                profileID: profile.id,
                state: .failed,
                userMessage: "\(profile.displayName) did not answer the health check.",
                recoverySuggestion: "Start the local service, then refresh backend status.",
                technicalDetails: [fallbackDetails, "URL: \(url.absoluteString)", "Timed out"].compactMap { $0 }.joined(separator: "\n\n")
            )
        }

        if let errorDescription = response.errorDescription {
            return BackendHealthReport(
                profileID: profile.id,
                state: .failed,
                userMessage: "\(profile.displayName) could not be reached.",
                recoverySuggestion: "Check the service address, port, and whether the backend is running.",
                technicalDetails: [fallbackDetails, "URL: \(url.absoluteString)", errorDescription, response.body].compactMap { $0 }.joined(separator: "\n\n")
            )
        }

        guard let statusCode = response.statusCode, (200..<300).contains(statusCode) else {
            return BackendHealthReport(
                profileID: profile.id,
                state: .failed,
                userMessage: "\(profile.displayName) answered, but did not report ready.",
                recoverySuggestion: "Check the health path and backend logs.",
                technicalDetails: [fallbackDetails, "URL: \(url.absoluteString)", "HTTP status: \(response.statusCode.map(String.init) ?? "unknown")", response.body].compactMap { $0 }.joined(separator: "\n\n")
            )
        }

        return BackendHealthReport(
            profileID: profile.id,
            state: .ready,
            userMessage: "\(profile.displayName) answered the health check.",
            technicalDetails: [fallbackDetails, "URL: \(url.absoluteString)", response.body].compactMap { $0 }.joined(separator: "\n\n")
        )
    }

    func waitForHTTPReady(
        profile: BackendProfile,
        url: URL,
        fallbackDetails: String
    ) -> BackendHealthReport {
        var lastResponse = BackendHTTPResult()
        for attempt in 1...12 {
            let response = httpClient.get(url: url, timeout: 1)
            lastResponse = response
            if let statusCode = response.statusCode, (200..<300).contains(statusCode), response.errorDescription == nil {
                return BackendHealthReport(
                    profileID: profile.id,
                    state: .ready,
                    userMessage: "\(profile.displayName) answered the health check.",
                    technicalDetails: [fallbackDetails, "URL: \(url.absoluteString)", response.body].filter { !$0.isEmpty }.joined(separator: "\n\n")
                )
            }
            if attempt < 12 {
                Thread.sleep(forTimeInterval: 1)
            }
        }

        return BackendHealthReport(
            profileID: profile.id,
            state: .failed,
            userMessage: "\(profile.displayName) did not answer the health check.",
            recoverySuggestion: "Start the local service, then refresh backend status.",
            technicalDetails: [
                fallbackDetails,
                "URL: \(url.absoluteString)",
                lastResponse.errorDescription,
                lastResponse.statusCode.map { "HTTP status: \($0)" },
                lastResponse.body
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        )
    }

    private func kokoroDockerHealthReport(
        profile: BackendProfile,
        docker: DockerRuntimeReport
    ) -> BackendHealthReport {
        guard let dockerExecutable = docker.executablePath else {
            return BackendHealthReport(
                profileID: profile.id,
                state: .missing,
                userMessage: "Docker was not found on this Mac.",
                recoverySuggestion: "Install Docker Desktop, then refresh backend status.",
                technicalDetails: docker.details
            )
        }
        guard let image = backendTrimmedNonEmpty(profile.dockerImage) else {
            return BackendHealthReport(
                profileID: profile.id,
                state: .missing,
                userMessage: "Kokoro needs the name of your installed Docker image.",
                recoverySuggestion: "Open the setup assistant, select Kokoro, and enter the image name you already use.",
                technicalDetails: docker.details
            )
        }

        let inspect = processExecutor.run(executable: dockerExecutable, arguments: ["image", "inspect", image])
        guard inspect.exitCode == 0 else {
            return BackendHealthReport(
                profileID: profile.id,
                state: .missing,
                userMessage: "\(image) was not found locally.",
                recoverySuggestion: "Check the image name in the setup assistant, or pull/build the image before running checks again.",
                technicalDetails: [docker.details, inspect.combinedOutput].compactMap { $0 }.joined(separator: "\n\n")
            )
        }

        let dockerDetails = [docker.details, inspect.combinedOutput].compactMap { $0 }.joined(separator: "\n\n")
        if let healthCheckURL = profile.healthCheckURL {
            let runningContainers = kokoroRunningContainers(
                dockerExecutable: dockerExecutable,
                profile: profile,
                image: image
            )
            if runningContainers.isEmpty {
                return BackendHealthReport(
                    profileID: profile.id,
                    state: .stopped,
                    userMessage: "\(image) is installed, but the Kokoro service is not running.",
                    recoverySuggestion: "Use Prepare Backend to start the local Kokoro service, then refresh status.",
                    technicalDetails: [
                        dockerDetails,
                        "Configured health URL: \(healthCheckURL.absoluteString)",
                        "No running Kokoro container was found for the configured image or container name."
                    ]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                )
            }
            return httpHealthReport(
                profile: profile,
                url: healthCheckURL,
                fallbackDetails: [
                    dockerDetails,
                    "Running Kokoro container(s):",
                    runningContainers.joined(separator: "\n")
                ]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            )
        }

        return BackendHealthReport(
            profileID: profile.id,
            state: .stopped,
            userMessage: "\(image) is available locally, but no Kokoro service address is configured.",
            recoverySuggestion: "Use Find Kokoro in the setup assistant, or enter the service URL before generating.",
            technicalDetails: dockerDetails
        )
    }

    private func kokoroRunningContainers(
        dockerExecutable: String,
        profile: BackendProfile,
        image: String
    ) -> [String] {
        var rows: [String] = []

        let imageResult = processExecutor.run(
            executable: dockerExecutable,
            arguments: [
                "ps",
                "--filter",
                "ancestor=\(image)",
                "--format",
                "{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"
            ]
        )
        rows.append(contentsOf: backendDockerTableRows(imageResult.combinedOutput))

        let candidateNames = [
            backendTrimmedNonEmpty(profile.containerName),
            defaultKokoroContainerName(for: profile)
        ]
        for name in candidateNames.compactMap({ $0 }) {
            let nameResult = processExecutor.run(
                executable: dockerExecutable,
                arguments: [
                    "ps",
                    "--filter",
                    "name=\(name)",
                    "--format",
                    "{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"
                ]
            )
            rows.append(contentsOf: backendDockerTableRows(nameResult.combinedOutput))
        }

        return Array(Set(rows)).sorted()
    }

    private func defaultKokoroContainerName(for profile: BackendProfile) -> String {
        let suffix = backendStableIdentifier(profile.id).replacingOccurrences(of: "-", with: "_")
        return "vibevoice_batch_\(suffix)"
    }

    private func externalServiceHealthReport(profile: BackendProfile) -> BackendHealthReport {
        guard let healthCheckURL = profile.healthCheckURL else {
            return BackendHealthReport(
                profileID: profile.id,
                state: .missing,
                userMessage: "\(profile.displayName) needs a service address before it can be checked.",
                recoverySuggestion: "Open the setup assistant and enter the local server address and health path."
            )
        }
        return httpHealthReport(profile: profile, url: healthCheckURL)
    }

    private func configuredRuntimeHealthReport(profile: BackendProfile) -> BackendHealthReport {
        if let healthCheckURL = profile.healthCheckURL {
            return httpHealthReport(profile: profile, url: healthCheckURL)
        }

        return BackendHealthReport(
            profileID: profile.id,
            state: .unknown,
            userMessage: "\(profile.displayName) needs runtime connection details before the app can verify it.",
            recoverySuggestion: "Open the setup assistant and choose how this backend runs, or enter a local service address with a health check path.",
            technicalDetails: [
                "Runtime: \(profile.runtime.rawValue)",
                "Install method: \(profile.installMethod.rawValue)",
                "Models: \(profile.requiredModels.map(\.id).joined(separator: ", "))",
                "Health check URL: not configured"
            ].joined(separator: "\n")
        )
    }
}

internal struct BackendSetupReporter {
    private let projectRoot: URL
    private let fileManager: FileManager
    private let dockerRuntimeInspector: BackendDockerRuntimeInspector
    private let processExecutor: BackendProcessExecutor
    private let healthChecker: BackendHealthChecker

    init(
        projectRoot: URL,
        fileManager: FileManager,
        dockerRuntimeInspector: BackendDockerRuntimeInspector,
        processExecutor: BackendProcessExecutor,
        healthChecker: BackendHealthChecker
    ) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
        self.dockerRuntimeInspector = dockerRuntimeInspector
        self.processExecutor = processExecutor
        self.healthChecker = healthChecker
    }

    func report(for profile: BackendProfile, generatedAt: Date = Date()) -> BackendSetupReport {
        var checks: [BackendSetupCheck] = []
        checks.append(systemCompatibilityCheck(for: profile))
        checks.append(projectFoldersCheck())

        switch profile.runtime {
        case .docker:
            let docker = dockerRuntimeInspector.report()
            checks.append(dockerSetupCheck(docker))
            checks.append(dockerImageCheck(profile: profile, docker: docker))
            checks.append(modelCacheCheck(profile: profile))
            if profile.engineType == .kokoro {
                checks.append(serviceEndpointCheck(profile: profile))
            }
        case .externalService:
            checks.append(serviceEndpointCheck(profile: profile))
        case .localPython, .comfyUI, .native:
            checks.append(runtimeConnectionCheck(profile: profile))
            if profile.healthCheckURL != nil {
                checks.append(serviceEndpointCheck(profile: profile))
            }
        }

        let health = healthChecker.healthReport(for: profile)
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

    private func systemCompatibilityCheck(for profile: BackendProfile) -> BackendSetupCheck {
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let architecture = backendCurrentArchitecture
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
        let result = processExecutor.run(executable: dockerExecutable, arguments: ["image", "inspect", image])
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

    private func serviceEndpointCheck(profile: BackendProfile) -> BackendSetupCheck {
        guard profile.runtime == .externalService || profile.engineType == .kokoro || profile.healthCheckURL != nil else {
            return BackendSetupCheck(
                id: "service-\(profile.id)",
                title: "Service endpoint",
                state: .waiting,
                message: "No service endpoint is required for this backend."
            )
        }
        guard let healthCheckURL = profile.healthCheckURL else {
            let backendName = profile.displayName
            return BackendSetupCheck(
                id: "service-\(profile.id)",
                title: "Service endpoint",
                state: .warning,
                message: "No \(backendName) service address has been saved yet.",
                recoverySuggestion: "If your install runs as a local server, enter its address and health path before generating."
            )
        }

        let health = healthChecker.httpHealthReport(profile: profile, url: healthCheckURL)
        return BackendSetupCheck(
            id: "service-\(profile.id)",
            title: "Service endpoint",
            state: health.state == .ready ? .passed : .warning,
            message: health.userMessage,
            recoverySuggestion: health.recoverySuggestion,
            technicalDetails: health.technicalDetails
        )
    }

    private func runtimeConnectionCheck(profile: BackendProfile) -> BackendSetupCheck {
        let hasHealthCheck = profile.healthCheckURL != nil
        return BackendSetupCheck(
            id: "runtime-\(profile.id)",
            title: "Runtime connection",
            state: hasHealthCheck ? .passed : .warning,
            message: hasHealthCheck ?
                "\(profile.displayName) has a checkable runtime connection." :
                "\(profile.displayName) needs runtime connection details before setup checks can verify it.",
            recoverySuggestion: hasHealthCheck ? nil :
                "Choose a runtime in the setup assistant, or enter the local service address and health path for this backend.",
            technicalDetails: [
                "Runtime: \(profile.runtime.rawValue)",
                "Install method: \(profile.installMethod.rawValue)",
                "Models: \(profile.requiredModels.map(\.id).joined(separator: ", "))"
            ].joined(separator: "\n")
        )
    }
}
