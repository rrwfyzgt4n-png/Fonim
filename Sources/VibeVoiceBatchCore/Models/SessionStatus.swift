import Foundation

public enum SessionStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case running
    case completed
    case failed
    case cancelled

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .draft: "Draft"
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}
