import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import VibeVoiceBatchCore

final class SpotlightIndexer {
    private let projectRoot: URL
    private var pendingTask: Task<Void, Never>?

    init(projectRoot: URL = AppDefaults.projectRoot) {
        self.projectRoot = projectRoot
    }

    func scheduleIndex(delayNanoseconds: UInt64 = 500_000_000) {
        pendingTask?.cancel()
        let projectRoot = projectRoot

        pendingTask = Task.detached(priority: .utility) {
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }

            do {
                try await Self.indexWorkspace(projectRoot: projectRoot)
            } catch {
                NSLog("Fonim Spotlight indexing failed: \(error.localizedDescription)")
            }
        }
    }

    static func indexWorkspace(projectRoot: URL = AppDefaults.projectRoot) async throws {
        let workspaceStore = WorkspaceFileStore(projectRoot: projectRoot)
        let sessionStore = SessionFileStore(projectRoot: projectRoot)
        let snapshot = try workspaceStore.loadSnapshot()
        let sessions = try sessionStore.loadSessions()
        let items = makeSearchableItems(snapshot: snapshot, sessions: sessions)

        try await deleteIndexedItems()
        guard !items.isEmpty else { return }
        try await index(items)
    }

    private static let domainIdentifier = "local.vibevoice.batch"

    private static func makeSearchableItems(
        snapshot: WorkspaceSnapshot,
        sessions: [SessionRecord]
    ) -> [CSSearchableItem] {
        var items: [CSSearchableItem] = []

        items += snapshot.projects.map { project in
            makeItem(
                id: "project.\(project.id)",
                title: project.title,
                description: project.notes.trimmedOrNil ?? "Fonim project",
                keywords: ["Fonim", "project", "narration"],
                contentType: .folder,
                createdAt: project.createdAt,
                updatedAt: project.updatedAt
            )
        }

        items += snapshot.scripts.map { script in
            makeItem(
                id: "script.\(script.id)",
                title: script.title,
                description: script.text.spotlightSummary(fallback: script.notes.trimmedOrNil ?? "Fonim script"),
                keywords: ["Fonim", "script", "narration", script.defaultBackendID, script.defaultVoice],
                contentType: .plainText,
                createdAt: script.createdAt,
                updatedAt: script.updatedAt
            )
        }

        items += snapshot.batches.map { batch in
            makeItem(
                id: "batch.\(batch.id)",
                title: batch.title,
                description: "\(batch.items.count) queued narration item\(batch.items.count == 1 ? "" : "s")",
                keywords: ["Fonim", "batch", "queue", batch.status.rawValue],
                contentType: .item,
                createdAt: batch.createdAt,
                updatedAt: batch.updatedAt
            )
        }

        items += snapshot.voicePresets
            .filter { !$0.isBuiltIn }
            .map { preset in
                makeItem(
                    id: "voice-preset.\(preset.id)",
                    title: preset.displayName,
                    description: preset.notes.trimmedOrNil ?? "Fonim voice profile",
                    keywords: ["Fonim", "voice", "profile", preset.backendID, preset.voiceID],
                    contentType: .item,
                    createdAt: preset.createdAt,
                    updatedAt: preset.updatedAt
                )
            }

        items += snapshot.generationPresets
            .filter { !$0.isBuiltIn }
            .map { preset in
                makeItem(
                    id: "generation-preset.\(preset.id)",
                    title: preset.displayName,
                    description: preset.notes.trimmedOrNil ?? "Fonim generation preset",
                    keywords: ["Fonim", "generation", "preset", preset.backendID],
                    contentType: .item,
                    createdAt: preset.createdAt,
                    updatedAt: preset.updatedAt
                )
            }

        items += sessions
            .filter { $0.metadata.status == .completed }
            .map { session in
                let duration = session.metadata.audioDurationSeconds.map { "Audio \($0.spotlightDuration)" }
                let description = [
                    duration,
                    "\(session.metadata.inputWordCount) words",
                    session.inputText.spotlightSummary(fallback: nil)
                ]
                    .compactMap { $0 }
                    .joined(separator: ". ")

                return makeItem(
                    id: "generation.\(session.id)",
                    title: session.id,
                    description: description.isEmpty ? "Fonim generation" : description,
                    keywords: ["Fonim", "generation", "audio", session.metadata.voice],
                    contentType: .audio,
                    createdAt: session.metadata.createdAt,
                    updatedAt: session.metadata.completedAt ?? session.metadata.createdAt,
                    path: session.outputURL?.path
                )
            }

        return items
    }

    private static func makeItem(
        id: String,
        title: String,
        description: String,
        keywords: [String],
        contentType: UTType,
        createdAt: Date,
        updatedAt: Date,
        path: String? = nil
    ) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: contentType)
        attributes.title = title
        attributes.contentDescription = description
        attributes.keywords = keywords
        attributes.contentCreationDate = createdAt
        attributes.contentModificationDate = updatedAt
        attributes.path = path

        let item = CSSearchableItem(
            uniqueIdentifier: id,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
        item.expirationDate = .distantFuture
        return item
    }

    private static func deleteIndexedItems() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func index(_ items: [CSSearchableItem]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private extension String {
    func spotlightSummary(fallback: String?) -> String {
        let normalized = split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let summary = String(normalized.prefix(280))
        return summary.trimmedOrNil ?? fallback ?? ""
    }
}

private extension Double {
    var spotlightDuration: String {
        let totalSeconds = max(0, Int(self.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
