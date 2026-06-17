import Foundation

public enum WorkstationToolbarKind: String, Equatable, Sendable {
    case editor
    case session
    case outputs
    case backends
    case workspace
}

public enum WorkstationSection: String, CaseIterable, Identifiable, Sendable {
    case projects
    case scripts
    case batches
    case voices
    case presets
    case history
    case outputs
    case backends

    public var id: String { rawValue }

    public var title: String {
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

    public var systemImage: String {
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

    public var toolbarKind: WorkstationToolbarKind {
        switch self {
        case .history:
            return .editor
        case .outputs:
            return .outputs
        case .backends:
            return .backends
        case .projects, .scripts, .batches, .voices, .presets:
            return .workspace
        }
    }
}

public enum WorkstationSelection: Hashable, Identifiable, Sendable {
    case section(WorkstationSection)
    case historySession(String)

    public var id: String {
        switch self {
        case .section(let section):
            return "section-\(section.rawValue)"
        case .historySession(let sessionID):
            return "history-\(sessionID)"
        }
    }

    public var toolbarKind: WorkstationToolbarKind {
        switch self {
        case .section(let section):
            return section.toolbarKind
        case .historySession:
            return .session
        }
    }
}
