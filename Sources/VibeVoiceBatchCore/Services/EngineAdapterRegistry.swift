import Foundation

public protocol EngineAdapterFactory {
    func isSupported(profile: BackendProfile) -> Bool
    func makeAdapter(profile: BackendProfile, projectRoot: URL) -> any EngineAdapter
}

public struct VibeVoiceEngineAdapterFactory: EngineAdapterFactory {
    public init() {}

    public func isSupported(profile: BackendProfile) -> Bool {
        profile.engineType == .vibeVoiceTTS
    }

    public func makeAdapter(profile: BackendProfile, projectRoot: URL) -> any EngineAdapter {
        VibeVoiceDockerAdapter(profile: profile, projectRoot: projectRoot)
    }
}

public struct KokoroEngineAdapterFactory: EngineAdapterFactory {
    public init() {}

    public func isSupported(profile: BackendProfile) -> Bool {
        profile.engineType == .kokoro
    }

    public func makeAdapter(profile: BackendProfile, projectRoot: URL) -> any EngineAdapter {
        KokoroHTTPAdapter(profile: profile, projectRoot: projectRoot)
    }
}

public struct ChatterboxEngineAdapterFactory: EngineAdapterFactory {
    public init() {}

    public func isSupported(profile: BackendProfile) -> Bool {
        profile.engineType == .chatterbox
    }

    public func makeAdapter(profile: BackendProfile, projectRoot: URL) -> any EngineAdapter {
        ChatterboxHTTPAdapter(profile: profile, projectRoot: projectRoot)
    }
}

public struct EngineAdapterRegistry {
    public static let `default` = EngineAdapterRegistry()

    private let factories: [any EngineAdapterFactory]

    public init(factories: [any EngineAdapterFactory] = [
        VibeVoiceEngineAdapterFactory(),
        KokoroEngineAdapterFactory(),
        ChatterboxEngineAdapterFactory()
    ]) {
        self.factories = factories
    }

    public func hasSupportedAdapter(for profile: BackendProfile) -> Bool {
        factories.contains { $0.isSupported(profile: profile) }
    }

    public func adapter(for profile: BackendProfile, projectRoot: URL = AppDefaults.projectRoot) -> any EngineAdapter {
        if let factory = factories.first(where: { $0.isSupported(profile: profile) }) {
            return factory.makeAdapter(profile: profile, projectRoot: projectRoot)
        }

        return UnavailableEngineAdapter(
            profile: profile,
            explanation: "\(profile.displayName) is registered, but no generation adapter is available yet.",
            recoverySuggestion: "Choose VibeVoice, Kokoro, or Chatterbox for generation."
        )
    }

    public func adapters(
        for profiles: [BackendProfile] = BackendProfiles.all,
        projectRoot: URL = AppDefaults.projectRoot
    ) -> [any EngineAdapter] {
        profiles.map { adapter(for: $0, projectRoot: projectRoot) }
    }

    public func supportedBackendIDs(for profiles: [BackendProfile] = BackendProfiles.all) -> Set<String> {
        Set(profiles.filter { hasSupportedAdapter(for: $0) }.map(\.id))
    }
}
