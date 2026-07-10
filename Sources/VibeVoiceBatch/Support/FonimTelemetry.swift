import Foundation
import OSLog
import os.signpost

enum FonimTelemetry {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "local.vibevoice.batch"
    private static let generationLogger = Logger(subsystem: subsystem, category: "GenerationSelection")
    private static let generationSignpostLog = OSLog(subsystem: subsystem, category: "GenerationSelection")

    static func selectedGeneration(kind: String, id: String) {
        generationLogger.info("Selected \(kind, privacy: .public) generation \(id, privacy: .public)")
        os_signpost(.event, log: generationSignpostLog, name: "GenerationSelected", "kind=%{public}@ id=%{public}@", kind as NSString, id as NSString)
    }

    static func detailAppeared(kind: String, id: String) {
        generationLogger.info("Displayed \(kind, privacy: .public) generation detail \(id, privacy: .public)")
        os_signpost(.event, log: generationSignpostLog, name: "GenerationDetailDisplayed", "kind=%{public}@ id=%{public}@", kind as NSString, id as NSString)
    }

    static func detailPaneChanged(sessionID: String, pane: String) {
        generationLogger.debug("Session \(sessionID, privacy: .public) pane \(pane, privacy: .public)")
        os_signpost(.event, log: generationSignpostLog, name: "GenerationPaneChanged", "session=%{public}@ pane=%{public}@", sessionID as NSString, pane as NSString)
    }

    static func sessionLogLoadStarted(sessionID: String) {
        generationLogger.debug("Started loading log for session \(sessionID, privacy: .public)")
        os_signpost(.event, log: generationSignpostLog, name: "SessionLogLoadStarted", "session=%{public}@", sessionID as NSString)
    }

    static func sessionLogLoadFinished(sessionID: String, characterCount: Int) {
        generationLogger.debug("Finished loading log for session \(sessionID, privacy: .public), characters \(characterCount, privacy: .public)")
        os_signpost(
            .event,
            log: generationSignpostLog,
            name: "SessionLogLoadFinished",
            "session=%{public}@ characters=%{public}d",
            sessionID as NSString,
            characterCount
        )
    }

    static func largeTextUpdated(kind: String, characterCount: Int) {
        generationLogger.debug("Updated \(kind, privacy: .public) text view, characters \(characterCount, privacy: .public)")
        os_signpost(
            .event,
            log: generationSignpostLog,
            name: "LargeTextUpdated",
            "kind=%{public}@ characters=%{public}d",
            kind as NSString,
            characterCount
        )
    }
}
