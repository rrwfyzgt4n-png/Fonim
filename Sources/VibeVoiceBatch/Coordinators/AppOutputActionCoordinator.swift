import AppKit
import Foundation
import VibeVoiceBatchCore

struct OutputArchiveSummary: Equatable {
    var archivedCount: Int
    var archivedIDs: Set<String>
    var failures: [String]
}

struct AppOutputActionCoordinator {
    private let fileStore: SessionFileStore
    private let quickLookPreviewer: QuickLookPreviewer

    init(fileStore: SessionFileStore, quickLookPreviewer: QuickLookPreviewer) {
        self.fileStore = fileStore
        self.quickLookPreviewer = quickLookPreviewer
    }

    func archiveDeletedSession(_ record: SessionRecord) throws -> URL {
        try fileStore.archiveDeletedSession(record)
    }

    func archiveDeletedSessions(_ records: [SessionRecord]) -> OutputArchiveSummary {
        var archivedCount = 0
        var archivedIDs: Set<String> = []
        var failures: [String] = []

        for record in records {
            do {
                _ = try fileStore.archiveDeletedSession(record)
                archivedCount += 1
                archivedIDs.insert(record.id)
            } catch {
                failures.append("\(record.id): \(error.localizedDescription)")
            }
        }

        return OutputArchiveSummary(
            archivedCount: archivedCount,
            archivedIDs: archivedIDs,
            failures: failures
        )
    }

    func openSessionFolder(_ record: SessionRecord) {
        NSWorkspace.shared.open(record.folderURL)
    }

    func revealOutputFile(_ record: SessionRecord) -> String {
        guard let outputURL = record.outputURL else {
            return "No WAV file for this session"
        }

        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        return "Revealed \(outputURL.lastPathComponent)"
    }

    func revealOutputURL(_ outputURL: URL) -> String {
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        return "Revealed \(outputURL.lastPathComponent)"
    }

    func copyOutputPath(_ record: SessionRecord) -> String {
        guard let outputURL = record.outputURL else {
            return "No WAV file for this session"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputURL.path, forType: .string)
        return "Copied output path"
    }

    func copyOutputPaths(_ records: [SessionRecord]) -> String {
        let paths = records.compactMap { $0.outputURL?.path }
        guard !paths.isEmpty else {
            return "No output paths selected"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        return "Copied \(paths.count) output path\(paths.count == 1 ? "" : "s")"
    }

    func quickLookOutputFile(_ record: SessionRecord) -> String {
        guard let outputURL = record.outputURL else {
            return "No WAV file for this session"
        }

        quickLookPreviewer.preview(outputURL)
        return "Previewing \(outputURL.lastPathComponent)"
    }

    func shareOutputFiles(_ records: [SessionRecord]) -> Bool {
        let urls = records.compactMap(\.outputURL)
        guard !urls.isEmpty else {
            return false
        }

        guard let contentView = NSApp.keyWindow?.contentView else {
            return false
        }

        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        return true
    }
}
