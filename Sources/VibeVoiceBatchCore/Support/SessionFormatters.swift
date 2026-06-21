import Foundation

public enum SessionFormatters {
    public static let sessionIDDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter
    }()

    public static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    public static func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "n/a" }
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return "\(minutes)m \(remainder)s"
    }

    public static func longDuration(_ seconds: Double?) -> String {
        guard let seconds else { return "no generated audio yet" }
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60

        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours) \(hours == 1 ? "hour" : "hours")")
        }
        if minutes > 0 {
            parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        }
        if remainingSeconds > 0 || parts.isEmpty {
            parts.append("\(remainingSeconds) \(remainingSeconds == 1 ? "second" : "seconds")")
        }

        guard parts.count > 1 else {
            return parts[0]
        }
        return parts.dropLast().joined(separator: " ") + " and " + parts.last!
    }

    public static func rtf(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2fx", value)
    }
}
