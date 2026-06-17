import Foundation

enum WorkstationSection: String, CaseIterable, Identifiable {
    case projects
    case scripts
    case batches
    case voices
    case presets
    case history
    case outputs
    case backends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .scripts: "Scripts"
        case .batches: "Batches"
        case .voices: "Voices"
        case .presets: "Presets"
        case .history: "History"
        case .outputs: "Outputs"
        case .backends: "Backends"
        }
    }

    var systemImage: String {
        switch self {
        case .projects: "folder"
        case .scripts: "doc.text"
        case .batches: "tray.full"
        case .voices: "waveform"
        case .presets: "slider.horizontal.3"
        case .history: "clock.arrow.circlepath"
        case .outputs: "music.note.list"
        case .backends: "server.rack"
        }
    }
}

enum WorkstationSelection: Hashable, Identifiable {
    case section(WorkstationSection)
    case historySession(String)

    var id: String {
        switch self {
        case .section(let section):
            return "section-\(section.rawValue)"
        case .historySession(let sessionID):
            return "history-\(sessionID)"
        }
    }
}
