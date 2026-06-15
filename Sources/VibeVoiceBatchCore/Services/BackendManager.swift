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

public struct BackendHTTPResult: Codable, Equatable, Sendable {
    public var statusCode: Int?
    public var body: String
    public var errorDescription: String?
    public var timedOut: Bool

    public init(
        statusCode: Int? = nil,
        body: String = "",
        errorDescription: String? = nil,
        timedOut: Bool = false
    ) {
        self.statusCode = statusCode
        self.body = body
        self.errorDescription = errorDescription
        self.timedOut = timedOut
    }
}

private struct DockerRuntimeOperationContext {
    var executablePath: String
    var report: DockerRuntimeReport
}

public final class BackendManager: @unchecked Sendable {
    public typealias DockerExecutableResolver = @Sendable () -> String?
    public typealias ProcessRunner = @Sendable (_ executable: String, _ arguments: [String]) -> BackendProcessResult
    public typealias HTTPRunner = @Sendable (_ url: URL) -> BackendHTTPResult?

    private let projectRoot: URL
    private let fileManager: FileManager
    private let dockerExecutableResolver: DockerExecutableResolver?
    private let processRunner: ProcessRunner?
    private let httpRunner: HTTPRunner?

    public init(
        projectRoot: URL = AppDefaults.projectRoot,
        fileManager: FileManager = .default,
        dockerExecutableResolver: DockerExecutableResolver? = nil,
        processRunner: ProcessRunner? = nil,
        httpRunner: HTTPRunner? = nil
    ) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
        self.dockerExecutableResolver = dockerExecutableResolver
        self.processRunner = processRunner
        self.httpRunner = httpRunner
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
            return BackendHealthReport(
                profileID: profile.id,
                state: .unknown,
                userMessage: "Backend checks for \(profile.displayName) have not been implemented yet.",
                recoverySuggestion: profile.engineType == .kokoro ?
                    "For Kokoro, choose Installed Docker Image or External Service in the setup assistant first." :
                    "Choose a configured backend before generating."
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

    public func diskUsageReport() -> BackendDiskUsageReport {
        BackendDiskUsageReport(
            projectRootBytes: directorySizeBytes(projectRoot),
            historyBytes: directorySizeBytes(projectRoot.historyDirectory),
            outputsBytes: directorySizeBytes(projectRoot.outputsDirectory),
            recoveredBytes: directorySizeBytes(projectRoot.recoveredDirectory),
            modelCacheBytes: directorySizeBytes(projectRoot.hfCacheDirectory)
        )
    }

    public func performOperation(_ kind: BackendOperationKind, for profile: BackendProfile) -> BackendOperationResult {
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

    public func performOperationAsync(_ kind: BackendOperationKind, for profile: BackendProfile) async -> BackendOperationResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.performOperation(kind, for: profile))
            }
        }
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
            if profile.engineType == .kokoro {
                checks.append(serviceEndpointCheck(profile: profile))
            }
        case .externalService:
            checks.append(serviceEndpointCheck(profile: profile))
        case .localPython, .comfyUI, .native:
            checks.append(
                BackendSetupCheck(
                    id: "runtime-\(profile.id)",
                    title: "Runtime",
                    state: .warning,
                    message: "Setup checks for \(profile.displayName) are limited for this runtime.",
                    recoverySuggestion: profile.engineType == .kokoro ?
                        "If your Kokoro install exposes a local server, choose External Service. If it uses a Docker image, choose Installed Docker Image." :
                        "Use a supported backend while additional installers are added."
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

    public func discoveryReport(for profile: BackendProfile, generatedAt: Date = Date()) -> BackendDiscoveryReport {
        guard profile.engineType == .kokoro else {
            return BackendDiscoveryReport(
                profileID: profile.id,
                generatedAt: generatedAt,
                candidates: [],
                message: "Automatic discovery is not available for \(profile.displayName) yet."
            )
        }

        let docker = dockerRuntimeReport()
        guard docker.isInstalled, docker.isRunning, let dockerExecutable = docker.executablePath else {
            return BackendDiscoveryReport(
                profileID: profile.id,
                generatedAt: generatedAt,
                candidates: [],
                message: docker.isInstalled ? "Docker Desktop is not running." : "Docker Desktop was not found.",
                technicalDetails: docker.details
            )
        }

        let images = runProcess(
            executable: dockerExecutable,
            arguments: ["images", "--format", "{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}"]
        )
        let containers = runProcess(
            executable: dockerExecutable,
            arguments: ["ps", "--format", "{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"]
        )

        var candidates = dockerContainerDiscoveryCandidates(from: containers.combinedOutput)
        let runningImages = Set(candidates.compactMap(\.dockerImage))
        candidates.append(
            contentsOf: dockerImageDiscoveryCandidates(from: images.combinedOutput)
                .filter { candidate in
                    guard let image = candidate.dockerImage else { return true }
                    return !runningImages.contains(image)
                }
        )

        return BackendDiscoveryReport(
            profileID: profile.id,
            generatedAt: generatedAt,
            candidates: candidates,
            message: candidates.isEmpty ? "No likely Kokoro runtime was found." : "Found \(candidates.count) likely Kokoro runtime\(candidates.count == 1 ? "" : "s").",
            technicalDetails: [docker.details, images.combinedOutput, containers.combinedOutput]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        )
    }

    public func discoveryReportAsync(for profile: BackendProfile, generatedAt: Date = Date()) async -> BackendDiscoveryReport {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.discoveryReport(for: profile, generatedAt: generatedAt))
            }
        }
    }

    public func catalogReport(for profile: BackendProfile, generatedAt: Date = Date()) -> BackendCatalogReport {
        guard profile.engineType == .kokoro else {
            return BackendCatalogReport(
                profileID: profile.id,
                generatedAt: generatedAt,
                models: [],
                voices: [],
                message: "Model and voice catalog is not available for \(profile.displayName) yet."
            )
        }
        guard let modelsURL = serviceURL(for: profile, path: "/v1/models"),
              let voicesURL = serviceURL(for: profile, path: "/v1/audio/voices") else {
            return BackendCatalogReport(
                profileID: profile.id,
                generatedAt: generatedAt,
                models: [],
                voices: [],
                message: "Kokoro needs a service address before models and voices can be read.",
                technicalDetails: "Add a service URL in the setup assistant."
            )
        }

        let modelsResponse = httpGet(url: modelsURL)
        let voicesResponse = httpGet(url: voicesURL)
        let models = parseKokoroModels(from: modelsResponse.body)
        let voices = parseKokoroVoices(from: voicesResponse.body)
        let ok = isSuccessfulHTTP(modelsResponse) && isSuccessfulHTTP(voicesResponse)

        return BackendCatalogReport(
            profileID: profile.id,
            generatedAt: generatedAt,
            models: models,
            voices: voices,
            message: ok ?
                "Loaded \(models.count) model\(models.count == 1 ? "" : "s") and \(voices.count) voice\(voices.count == 1 ? "" : "s")." :
                "Could not read every Kokoro model and voice list.",
            technicalDetails: [
                "Models URL: \(modelsURL.absoluteString)",
                httpDetails(modelsResponse),
                "Voices URL: \(voicesURL.absoluteString)",
                httpDetails(voicesResponse)
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        )
    }

    public func catalogReportAsync(for profile: BackendProfile, generatedAt: Date = Date()) async -> BackendCatalogReport {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.catalogReport(for: profile, generatedAt: generatedAt))
            }
        }
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
        guard let image = profile.dockerImage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !image.isEmpty else {
            return BackendHealthReport(
                profileID: profile.id,
                state: .missing,
                userMessage: "Kokoro needs the name of your installed Docker image.",
                recoverySuggestion: "Open the setup assistant, select Kokoro, and enter the image name you already use.",
                technicalDetails: docker.details
            )
        }

        let inspect = runProcess(executable: dockerExecutable, arguments: ["image", "inspect", image])
        guard inspect.exitCode == 0 else {
            return BackendHealthReport(
                profileID: profile.id,
                state: .missing,
                userMessage: "\(image) was not found locally.",
                recoverySuggestion: "Check the image name in the setup assistant, or pull/build the image before running checks again.",
                technicalDetails: [docker.details, inspect.combinedOutput].compactMap { $0 }.joined(separator: "\n\n")
            )
        }

        if let healthCheckURL = profile.healthCheckURL {
            return httpHealthReport(
                profile: profile,
                url: healthCheckURL,
                fallbackDetails: [docker.details, inspect.combinedOutput].compactMap { $0 }.joined(separator: "\n\n")
            )
        }

        return BackendHealthReport(
            profileID: profile.id,
            state: .stopped,
            userMessage: "\(image) is available locally, but no Kokoro service address is configured.",
            recoverySuggestion: "Use Find Kokoro in the setup assistant, or enter the service URL before generating.",
            technicalDetails: [docker.details, inspect.combinedOutput].compactMap { $0 }.joined(separator: "\n\n")
        )
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

    private func httpHealthReport(
        profile: BackendProfile,
        url: URL,
        fallbackDetails: String? = nil
    ) -> BackendHealthReport {
        let response = httpGet(url: url)

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

    private func httpGet(url: URL, timeout: TimeInterval = 5) -> BackendHTTPResult {
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

    private func isSuccessfulHTTP(_ response: BackendHTTPResult) -> Bool {
        guard !response.timedOut, response.errorDescription == nil, let statusCode = response.statusCode else {
            return false
        }
        return (200..<300).contains(statusCode)
    }

    private func httpDetails(_ response: BackendHTTPResult) -> String {
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

    private func serviceURL(for profile: BackendProfile, path: String) -> URL? {
        let referenceURL = profile.healthCheckURL ?? profile.generateEndpoint
        guard let referenceURL,
              var components = URLComponents(url: referenceURL, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func parseKokoroModels(from body: String) -> [BackendCatalogModel] {
        parseCatalogEntries(from: body, preferredCollectionKey: "data").map { entry in
            BackendCatalogModel(id: entry.id, displayName: entry.name ?? entry.id, owner: entry.owner)
        }
    }

    private func parseKokoroVoices(from body: String) -> [BackendCatalogVoice] {
        parseCatalogEntries(from: body, preferredCollectionKey: "voices").map { entry in
            BackendCatalogVoice(id: entry.id, displayName: entry.name ?? entry.id)
        }
    }

    private struct CatalogEntry {
        var id: String
        var name: String?
        var owner: String?
    }

    private func parseCatalogEntries(from body: String, preferredCollectionKey: String) -> [CatalogEntry] {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let dictionary = json as? [String: Any] {
            if let preferred = dictionary[preferredCollectionKey] {
                return parseCatalogCollection(preferred)
            }
            if let dataCollection = dictionary["data"] {
                return parseCatalogCollection(dataCollection)
            }
            if let voicesCollection = dictionary["voices"] {
                return parseCatalogCollection(voicesCollection)
            }
        }

        return parseCatalogCollection(json)
    }

    private func parseCatalogCollection(_ value: Any) -> [CatalogEntry] {
        if let strings = value as? [String] {
            return strings.map { CatalogEntry(id: $0, name: $0, owner: nil) }
        }

        guard let array = value as? [Any] else { return [] }
        return array.compactMap { item in
            if let string = item as? String {
                return CatalogEntry(id: string, name: string, owner: nil)
            }
            guard let dictionary = item as? [String: Any] else { return nil }
            let id = dictionary["id"] as? String ??
                dictionary["name"] as? String ??
                dictionary["model"] as? String
            guard let id, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return CatalogEntry(
                id: id,
                name: dictionary["name"] as? String ?? dictionary["displayName"] as? String,
                owner: dictionary["owned_by"] as? String ?? dictionary["owner"] as? String
            )
        }
    }

    private func installBackend(_ profile: BackendProfile) -> BackendOperationResult {
        let startedAt = Date()
        guard profile.runtime == .docker, profile.installMethod == .managedDockerImage else {
            return operationResult(
                profile: profile,
                kind: .install,
                status: .skipped,
                startedAt: startedAt,
                message: "Managed install is not available for \(profile.displayName) yet.",
                recoverySuggestion: "Use a backend with a managed local runtime or connect an external backend."
            )
        }
        let directoryLog = ensureProjectDirectoriesLog()
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

        let pull = runProcess(executable: docker.executablePath, arguments: ["pull", image])
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

        let pull = runProcess(executable: docker.executablePath, arguments: ["pull", image])
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
        let directoryLog = ensureProjectDirectoriesLog()
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
        let inspect = runProcess(executable: docker.executablePath, arguments: ["image", "inspect", image])
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

        let list = runProcess(
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

        let stop = runProcess(executable: docker.executablePath, arguments: ["stop"] + names)
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

    private func runHealthCheck(_ profile: BackendProfile) -> BackendOperationResult {
        let startedAt = Date()
        let report = healthReport(for: profile)
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
        let directoryLog = ensureProjectDirectoriesLog()
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
        let directoryLog = ensureProjectDirectoriesLog()
        let recovered = recoverStrayGeneratedWAV(reason: "backend_reset")
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

    private func serviceEndpointCheck(profile: BackendProfile) -> BackendSetupCheck {
        guard profile.engineType == .kokoro else {
            return BackendSetupCheck(
                id: "service-\(profile.id)",
                title: "Service endpoint",
                state: .waiting,
                message: "No service endpoint is required for this backend."
            )
        }
        guard let healthCheckURL = profile.healthCheckURL else {
            return BackendSetupCheck(
                id: "service-\(profile.id)",
                title: "Service endpoint",
                state: .warning,
                message: "No Kokoro service address has been saved yet.",
                recoverySuggestion: "If your Kokoro install runs as a local server, enter its address and health path. If it is only an image, this can wait until the adapter phase."
            )
        }

        let health = httpHealthReport(profile: profile, url: healthCheckURL)
        return BackendSetupCheck(
            id: "service-\(profile.id)",
            title: "Service endpoint",
            state: health.state == .ready ? .passed : .warning,
            message: health.userMessage,
            recoverySuggestion: health.recoverySuggestion,
            technicalDetails: health.technicalDetails
        )
    }

    private func dockerImageDiscoveryCandidates(from output: String) -> [BackendDiscoveryCandidate] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> BackendDiscoveryCandidate? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard let image = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !image.isEmpty,
                      !image.contains("<none>"),
                      isLikelyKokoro(text: image) else {
                    return nil
                }
                let imageID = fields.dropFirst().first ?? ""
                let size = fields.dropFirst(2).first ?? ""
                return BackendDiscoveryCandidate(
                    id: "image-\(stableIdentifier(image))",
                    title: image,
                    confidence: .medium,
                    connectionKind: .installedDockerImage,
                    dockerImage: image,
                    serviceBaseURL: nil,
                    notes: "Image found locally. Start it or enter the service URL if it is already running.",
                    technicalDetails: [imageID, size].filter { !$0.isEmpty }.joined(separator: "  ")
                )
            }
    }

    private func dockerContainerDiscoveryCandidates(from output: String) -> [BackendDiscoveryCandidate] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> BackendDiscoveryCandidate? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 4 else { return nil }
                let name = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let image = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let ports = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
                let status = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
                guard isLikelyKokoro(text: [name, image].joined(separator: " ")) else { return nil }

                let serviceBaseURL = serviceURL(fromDockerPorts: ports)
                return BackendDiscoveryCandidate(
                    id: "container-\(stableIdentifier(name))",
                    title: name.isEmpty ? image : name,
                    confidence: serviceBaseURL == nil ? .medium : .high,
                    connectionKind: .installedDockerImage,
                    dockerImage: image.isEmpty ? nil : image,
                    containerName: name.isEmpty ? nil : name,
                    serviceBaseURL: serviceBaseURL,
                    notes: serviceBaseURL == nil ?
                        "Running container found. Enter its local service address if it is not published to the Mac." :
                        "Running container found and a local service address was detected.",
                    technicalDetails: [image, ports, status].filter { !$0.isEmpty }.joined(separator: "\n")
                )
            }
    }

    private func serviceURL(fromDockerPorts ports: String) -> String? {
        for mapping in ports.split(separator: ",") {
            let text = mapping.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let arrow = text.range(of: "->") else { continue }
            let hostSide = text[..<arrow.lowerBound]
            guard let colon = hostSide.lastIndex(of: ":") else { continue }
            let port = String(hostSide[hostSide.index(after: colon)...])
            guard Int(port) != nil else { continue }
            return "http://127.0.0.1:\(port)"
        }
        return nil
    }

    private func isLikelyKokoro(text: String) -> Bool {
        text.localizedCaseInsensitiveContains("kokoro")
    }

    private func stableIdentifier(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar).lowercased() : "-"
        }
        .joined()
        .split(separator: "-")
        .joined(separator: "-")
    }

    private func dockerRuntimeForOperation(
        profile: BackendProfile,
        kind: BackendOperationKind,
        startedAt: Date,
        requireRunning: Bool = true
    ) -> DockerRuntimeOperationContext? {
        let docker = dockerRuntimeReport()
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
        let docker = dockerRuntimeReport()
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

    private func ensureProjectDirectoriesLog() -> String {
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

    private func recoverStrayGeneratedWAV(reason: String) -> URL? {
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

    private func directorySizeBytes(_ url: URL) -> UInt64 {
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

    private func uniqueURL(_ url: URL) -> URL {
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
