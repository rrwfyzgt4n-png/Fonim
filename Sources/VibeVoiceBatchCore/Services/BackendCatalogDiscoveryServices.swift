import Foundation

internal struct BackendCatalogParser {
    func parseKokoroModels(from body: String) -> [BackendCatalogModel] {
        parseCatalogEntries(from: body, preferredCollectionKey: "data").map { entry in
            BackendCatalogModel(id: entry.id, displayName: entry.name ?? entry.id, owner: entry.owner)
        }
    }

    func parseKokoroVoices(from body: String) -> [BackendCatalogVoice] {
        parseCatalogEntries(from: body, preferredCollectionKey: "voices").map { entry in
            BackendCatalogVoice(id: entry.id, displayName: entry.name ?? entry.id)
        }
    }

    func parseChatterboxModels(from body: String) -> [BackendCatalogModel] {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let dictionary = json as? [String: Any] else {
            return []
        }
        let isLoaded = dictionary["loaded"] as? Bool
        let modelType = dictionary["type"] as? String
        let className = dictionary["class_name"] as? String
        let trimmedModelType = modelType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = (trimmedModelType?.isEmpty == false ? trimmedModelType : nil) ?? "chatterbox"
        let displayName = [className, modelType]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [
            BackendCatalogModel(
                id: identifier == "original" ? "chatterbox" : identifier,
                displayName: displayName.isEmpty ? "Chatterbox TTS" : displayName + (isLoaded == false ? " (not loaded)" : ""),
                owner: "chatterbox"
            )
        ]
    }

    func parseChatterboxPredefinedVoices(from body: String) -> [BackendCatalogVoice] {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        return parseChatterboxVoiceCollection(json, prefix: "", suffix: "")
    }

    func parseChatterboxReferenceVoices(from body: String) -> [BackendCatalogVoice] {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        return parseChatterboxVoiceCollection(json, prefix: "reference:", suffix: " (Reference)")
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

    private func parseChatterboxVoiceCollection(_ value: Any, prefix: String, suffix: String) -> [BackendCatalogVoice] {
        if let strings = value as? [String] {
            return strings.map { voice in
                BackendCatalogVoice(id: "\(prefix)\(voice)", displayName: "\(voice)\(suffix)")
            }
        }

        guard let array = value as? [Any] else { return [] }
        return array.compactMap { item in
            if let string = item as? String {
                return BackendCatalogVoice(id: "\(prefix)\(string)", displayName: "\(string)\(suffix)")
            }
            guard let dictionary = item as? [String: Any] else { return nil }
            let id = dictionary["filename"] as? String ??
                dictionary["id"] as? String ??
                dictionary["name"] as? String
            guard let id, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let displayName = dictionary["display_name"] as? String ??
                dictionary["displayName"] as? String ??
                dictionary["name"] as? String ??
                id
            return BackendCatalogVoice(id: "\(prefix)\(id)", displayName: "\(displayName)\(suffix)")
        }
    }
}

internal struct BackendDiscoveryParser {
    func dockerImageDiscoveryCandidates(from output: String) -> [BackendDiscoveryCandidate] {
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
                    id: "image-\(backendStableIdentifier(image))",
                    title: image,
                    confidence: .medium,
                    connectionKind: .installedDockerImage,
                    dockerImage: image,
                    containerName: "vibevoice_batch_kokoro_tts",
                    serviceBaseURL: "http://127.0.0.1:8880",
                    notes: "Image found locally. Prepare can start an app-owned Kokoro service on port 8880.",
                    technicalDetails: [imageID, size].filter { !$0.isEmpty }.joined(separator: "  ")
                )
            }
    }

    func dockerContainerDiscoveryCandidates(from output: String) -> [BackendDiscoveryCandidate] {
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
                    id: "container-\(backendStableIdentifier(name))",
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
}

internal struct BackendCatalogReporter {
    private let httpClient: BackendHTTPClient
    private let catalogParser: BackendCatalogParser

    init(httpClient: BackendHTTPClient, catalogParser: BackendCatalogParser) {
        self.httpClient = httpClient
        self.catalogParser = catalogParser
    }

    func report(for profile: BackendProfile, generatedAt: Date = Date()) -> BackendCatalogReport {
        switch profile.engineType {
        case .kokoro:
            return kokoroReport(for: profile, generatedAt: generatedAt)
        case .chatterbox:
            return chatterboxReport(for: profile, generatedAt: generatedAt)
        default:
            return BackendCatalogReport(
                profileID: profile.id,
                generatedAt: generatedAt,
                models: [],
                voices: [],
                message: "Model and voice catalog is not available for \(profile.displayName) yet."
            )
        }
    }

    private func kokoroReport(for profile: BackendProfile, generatedAt: Date) -> BackendCatalogReport {
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

        let modelsResponse = httpClient.get(url: modelsURL)
        let voicesResponse = httpClient.get(url: voicesURL)
        let models = catalogParser.parseKokoroModels(from: modelsResponse.body)
        let voices = catalogParser.parseKokoroVoices(from: voicesResponse.body)
        let ok = httpClient.isSuccessful(modelsResponse) && httpClient.isSuccessful(voicesResponse)

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
                httpClient.details(modelsResponse),
                "Voices URL: \(voicesURL.absoluteString)",
                httpClient.details(voicesResponse)
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        )
    }

    private func chatterboxReport(for profile: BackendProfile, generatedAt: Date) -> BackendCatalogReport {
        guard let modelURL = serviceURL(for: profile, path: "/api/model-info"),
              let predefinedURL = serviceURL(for: profile, path: "/get_predefined_voices"),
              let referencesURL = serviceURL(for: profile, path: "/get_reference_files") else {
            return BackendCatalogReport(
                profileID: profile.id,
                generatedAt: generatedAt,
                models: [],
                voices: [],
                message: "Chatterbox needs a service address before models and voices can be read.",
                technicalDetails: "Add a service URL in the setup assistant."
            )
        }

        let modelResponse = httpClient.get(url: modelURL)
        let predefinedResponse = httpClient.get(url: predefinedURL)
        let referencesResponse = httpClient.get(url: referencesURL)
        let models = catalogParser.parseChatterboxModels(from: modelResponse.body)
        let predefinedVoices = catalogParser.parseChatterboxPredefinedVoices(from: predefinedResponse.body)
        let referenceVoices = catalogParser.parseChatterboxReferenceVoices(from: referencesResponse.body)
        let voices = (predefinedVoices + referenceVoices).sorted { lhs, rhs in
            lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        let ok = httpClient.isSuccessful(modelResponse) &&
            httpClient.isSuccessful(predefinedResponse) &&
            httpClient.isSuccessful(referencesResponse)

        return BackendCatalogReport(
            profileID: profile.id,
            generatedAt: generatedAt,
            models: models.isEmpty ? [BackendCatalogModel(id: "chatterbox", displayName: "Chatterbox TTS")] : models,
            voices: voices,
            message: ok ?
                "Loaded Chatterbox model state and \(voices.count) voice\(voices.count == 1 ? "" : "s")." :
                "Could not read every Chatterbox model and voice list.",
            technicalDetails: [
                "Model URL: \(modelURL.absoluteString)",
                httpClient.details(modelResponse),
                "Predefined Voices URL: \(predefinedURL.absoluteString)",
                httpClient.details(predefinedResponse),
                "Reference Voices URL: \(referencesURL.absoluteString)",
                httpClient.details(referencesResponse)
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        )
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
}

internal struct BackendDiscoveryReporter {
    private let dockerRuntimeInspector: BackendDockerRuntimeInspector
    private let processExecutor: BackendProcessExecutor
    private let httpClient: BackendHTTPClient
    private let discoveryParser: BackendDiscoveryParser

    init(
        dockerRuntimeInspector: BackendDockerRuntimeInspector,
        processExecutor: BackendProcessExecutor,
        httpClient: BackendHTTPClient,
        discoveryParser: BackendDiscoveryParser
    ) {
        self.dockerRuntimeInspector = dockerRuntimeInspector
        self.processExecutor = processExecutor
        self.httpClient = httpClient
        self.discoveryParser = discoveryParser
    }

    func report(for profile: BackendProfile, generatedAt: Date = Date()) -> BackendDiscoveryReport {
        if profile.engineType == .chatterbox {
            return chatterboxDiscoveryReport(for: profile, generatedAt: generatedAt)
        }
        guard profile.engineType == .kokoro else {
            return BackendDiscoveryReport(
                profileID: profile.id,
                generatedAt: generatedAt,
                candidates: [],
                message: "Automatic discovery is not available for \(profile.displayName) yet."
            )
        }

        let docker = dockerRuntimeInspector.report()
        guard docker.isInstalled, docker.isRunning, let dockerExecutable = docker.executablePath else {
            return BackendDiscoveryReport(
                profileID: profile.id,
                generatedAt: generatedAt,
                candidates: [],
                message: docker.isInstalled ? "Docker Desktop is not running." : "Docker Desktop was not found.",
                technicalDetails: docker.details
            )
        }

        let images = processExecutor.run(
            executable: dockerExecutable,
            arguments: ["images", "--format", "{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}"]
        )
        let containers = processExecutor.run(
            executable: dockerExecutable,
            arguments: ["ps", "--format", "{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"]
        )

        var candidates = discoveryParser.dockerContainerDiscoveryCandidates(from: containers.combinedOutput)
        let runningImages = Set(candidates.compactMap(\.dockerImage))
        candidates.append(
            contentsOf: discoveryParser.dockerImageDiscoveryCandidates(from: images.combinedOutput)
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

    private func chatterboxDiscoveryReport(for profile: BackendProfile, generatedAt: Date) -> BackendDiscoveryReport {
        guard let healthCheckURL = profile.healthCheckURL else {
            return BackendDiscoveryReport(
                profileID: profile.id,
                generatedAt: generatedAt,
                candidates: [],
                message: "No Chatterbox service address has been configured yet."
            )
        }

        let response = httpClient.get(url: healthCheckURL)
        guard httpClient.isSuccessful(response) else {
            return BackendDiscoveryReport(
                profileID: profile.id,
                generatedAt: generatedAt,
                candidates: [],
                message: "No running Chatterbox service was found at the configured address.",
                technicalDetails: httpClient.details(response)
            )
        }

        let baseURL = serviceBaseURL(from: healthCheckURL)
        let candidate = BackendDiscoveryCandidate(
            id: "service-\(backendStableIdentifier(baseURL))",
            title: "Chatterbox service",
            confidence: .high,
            connectionKind: .externalService,
            serviceBaseURL: baseURL,
            healthPath: "/api/model-info",
            generatePath: "/tts",
            modelID: "chatterbox",
            defaultVoice: "Emily.wav",
            notes: "A local Chatterbox service answered on \(baseURL).",
            technicalDetails: httpClient.details(response)
        )

        return BackendDiscoveryReport(
            profileID: profile.id,
            generatedAt: generatedAt,
            candidates: [candidate],
            message: "Found a running Chatterbox service.",
            technicalDetails: httpClient.details(response)
        )
    }

    private func serviceBaseURL(from url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "http://127.0.0.1:8004"
    }
}
