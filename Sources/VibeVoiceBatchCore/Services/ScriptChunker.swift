import Foundation

public struct ScriptChunk: Equatable, Sendable {
    public var title: String
    public var text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    public var wordCount: Int {
        TextMetrics.wordCount(in: text)
    }
}

public enum ScriptChunker {
    public static func chunks(
        from text: String,
        baseTitle: String = "Imported Script",
        preferredMaxWords: Int = 220
    ) -> [ScriptChunk] {
        let timestamped = timestampedChunks(from: text, preferredMaxWords: preferredMaxWords)
        if !timestamped.isEmpty {
            return timestamped
        }

        let blocks = naturalBlocks(from: text)
        let expanded = blocks.flatMap { splitLargeBlock($0, preferredMaxWords: preferredMaxWords) }
        return expanded.enumerated().map { index, block in
            ScriptChunk(title: title(for: block, baseTitle: baseTitle, index: index + 1), text: block)
        }
    }

    public static func containsTimestampMarkers(in text: String) -> Bool {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .contains { timestampMarkerTitle(from: $0) != nil }
    }

    private static func naturalBlocks(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var blocks: [String] = []
        var current: [String] = []

        func flush() {
            let block = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !block.isEmpty {
                blocks.append(block)
            }
            current.removeAll(keepingCapacity: true)
        }

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if isDelimiterLine(line) || line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flush()
            } else {
                current.append(line)
            }
        }
        flush()
        return blocks
    }

    private static func timestampedChunks(from text: String, preferredMaxWords: Int) -> [ScriptChunk] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var chunks: [ScriptChunk] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func flush() {
            guard let currentTitle else {
                currentLines.removeAll(keepingCapacity: true)
                return
            }
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else {
                currentLines.removeAll(keepingCapacity: true)
                return
            }

            let splitBody = splitLargeBlock(body, preferredMaxWords: preferredMaxWords)
            if splitBody.count == 1 {
                chunks.append(ScriptChunk(title: currentTitle, text: body))
            } else {
                for (index, text) in splitBody.enumerated() {
                    chunks.append(ScriptChunk(title: "\(currentTitle) \(index + 1)", text: text))
                }
            }
            currentLines.removeAll(keepingCapacity: true)
        }

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let title = timestampMarkerTitle(from: line) {
                flush()
                currentTitle = title
                continue
            }
            if isMarkdownMarkerLine(line) || isDelimiterLine(line) {
                flush()
                currentTitle = nil
                continue
            }
            if currentTitle != nil {
                currentLines.append(line)
            }
        }
        flush()
        return chunks
    }

    private static func splitLargeBlock(_ block: String, preferredMaxWords: Int) -> [String] {
        guard TextMetrics.wordCount(in: block) > preferredMaxWords else { return [block] }
        let sentences = block.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard sentences.count > 1 else { return [block] }

        var chunks: [String] = []
        var current: [String] = []
        for sentence in sentences {
            let candidate = (current + [sentence]).joined(separator: ". ")
            if !current.isEmpty && TextMetrics.wordCount(in: candidate) > preferredMaxWords {
                chunks.append(current.joined(separator: ". ") + ".")
                current = [sentence]
            } else {
                current.append(sentence)
            }
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: ". ") + ".")
        }
        return chunks
    }

    private static func isDelimiterLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }
        let delimiterCharacters = CharacterSet(charactersIn: "-_*=")
        return trimmed.unicodeScalars.allSatisfy { delimiterCharacters.contains($0) }
    }

    private static func isMarkdownMarkerLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("**[") && trimmed.hasSuffix("]**")
    }

    private static func timestampMarkerTitle(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("**["), trimmed.hasSuffix("]**") else { return nil }
        let inner = String(trimmed.dropFirst(3).dropLast(3))
        guard inner.range(of: #"~?\d{1,2}:\d{2}"#, options: .regularExpression) != nil else {
            return nil
        }
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func title(for text: String, baseTitle: String, index: Int) -> String {
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#")))
        guard let firstLine, !firstLine.isEmpty else {
            return "\(baseTitle) \(index)"
        }
        return String(firstLine.prefix(56))
    }
}
