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

public final class BackendManager: @unchecked Sendable {
    public typealias DockerExecutableResolver = BackendDockerExecutableResolver
    public typealias ProcessRunner = BackendProcessRunner
    public typealias HTTPRunner = BackendHTTPRunner

    private let dockerRuntimeInspector: BackendDockerRuntimeInspector
    private let diskUsageAnalyzer: BackendDiskUsageAnalyzer
    private let healthChecker: BackendHealthChecker
    private let setupReporter: BackendSetupReporter
    private let discoveryReporter: BackendDiscoveryReporter
    private let catalogReporter: BackendCatalogReporter
    private let operationExecutor: BackendOperationExecutor

    public init(
        projectRoot: URL = AppDefaults.projectRoot,
        fileManager: FileManager = .default,
        dockerExecutableResolver: DockerExecutableResolver? = nil,
        processRunner: ProcessRunner? = nil,
        httpRunner: HTTPRunner? = nil
    ) {
        let processExecutor = BackendProcessExecutor(
            fileManager: fileManager,
            dockerExecutableResolver: dockerExecutableResolver,
            processRunner: processRunner
        )
        let dockerRuntimeInspector = BackendDockerRuntimeInspector(processExecutor: processExecutor)
        let httpClient = BackendHTTPClient(httpRunner: httpRunner)
        let catalogParser = BackendCatalogParser()
        let discoveryParser = BackendDiscoveryParser()
        let fileUtility = BackendRuntimeFileUtility(projectRoot: projectRoot, fileManager: fileManager)
        let healthChecker = BackendHealthChecker(
            dockerRuntimeInspector: dockerRuntimeInspector,
            processExecutor: processExecutor,
            httpClient: httpClient
        )
        self.dockerRuntimeInspector = dockerRuntimeInspector
        self.diskUsageAnalyzer = BackendDiskUsageAnalyzer(projectRoot: projectRoot, fileManager: fileManager)
        self.healthChecker = healthChecker
        self.setupReporter = BackendSetupReporter(
            projectRoot: projectRoot,
            fileManager: fileManager,
            dockerRuntimeInspector: dockerRuntimeInspector,
            processExecutor: processExecutor,
            healthChecker: healthChecker
        )
        self.discoveryReporter = BackendDiscoveryReporter(
            dockerRuntimeInspector: dockerRuntimeInspector,
            processExecutor: processExecutor,
            discoveryParser: discoveryParser
        )
        self.catalogReporter = BackendCatalogReporter(
            httpClient: httpClient,
            catalogParser: catalogParser
        )
        self.operationExecutor = BackendOperationExecutor(
            projectRoot: projectRoot,
            dockerRuntimeInspector: dockerRuntimeInspector,
            processExecutor: processExecutor,
            httpClient: httpClient,
            healthChecker: healthChecker,
            fileUtility: fileUtility
        )
    }

    public func registeredProfiles() -> [BackendProfile] {
        BackendProfiles.all
    }

    public func profile(id: String) -> BackendProfile? {
        registeredProfiles().first { $0.id == id }
    }

    public func healthReport(for profile: BackendProfile) -> BackendHealthReport {
        healthChecker.healthReport(for: profile)
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
        dockerRuntimeInspector.report()
    }

    public func backendDiskUsageBytes() -> UInt64? {
        diskUsageAnalyzer.backendDiskUsageBytes()
    }

    public func diskUsageReport() -> BackendDiskUsageReport {
        diskUsageAnalyzer.report()
    }

    public func performOperation(_ kind: BackendOperationKind, for profile: BackendProfile) -> BackendOperationResult {
        operationExecutor.perform(kind, for: profile)
    }

    public func performOperationAsync(_ kind: BackendOperationKind, for profile: BackendProfile) async -> BackendOperationResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.performOperation(kind, for: profile))
            }
        }
    }

    public func setupReport(for profile: BackendProfile, generatedAt: Date = Date()) -> BackendSetupReport {
        setupReporter.report(for: profile, generatedAt: generatedAt)
    }

    public func setupReportAsync(for profile: BackendProfile, generatedAt: Date = Date()) async -> BackendSetupReport {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.setupReport(for: profile, generatedAt: generatedAt))
            }
        }
    }

    public func discoveryReport(for profile: BackendProfile, generatedAt: Date = Date()) -> BackendDiscoveryReport {
        discoveryReporter.report(for: profile, generatedAt: generatedAt)
    }

    public func discoveryReportAsync(for profile: BackendProfile, generatedAt: Date = Date()) async -> BackendDiscoveryReport {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.discoveryReport(for: profile, generatedAt: generatedAt))
            }
        }
    }

    public func catalogReport(for profile: BackendProfile, generatedAt: Date = Date()) -> BackendCatalogReport {
        catalogReporter.report(for: profile, generatedAt: generatedAt)
    }

    public func catalogReportAsync(for profile: BackendProfile, generatedAt: Date = Date()) async -> BackendCatalogReport {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.catalogReport(for: profile, generatedAt: generatedAt))
            }
        }
    }
}
