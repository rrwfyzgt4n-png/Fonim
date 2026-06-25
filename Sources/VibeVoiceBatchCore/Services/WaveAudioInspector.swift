import Foundation

public enum WaveAudioInspector {
    public static func durationSeconds(for url: URL) throws -> Double? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let header = try handle.read(upToCount: 12),
              header.count == 12,
              header.asciiString(in: 0..<4) == "RIFF",
              header.asciiString(in: 8..<12) == "WAVE" else {
            return nil
        }

        var offset: UInt64 = 12
        var byteRate: UInt32?
        var dataSize: UInt64?

        while let chunkHeader = try handle.read(upToCount: 8), chunkHeader.count == 8 {
            let chunkID = chunkHeader.asciiString(in: 0..<4)
            let chunkSize = UInt64(chunkHeader.littleEndianUInt32(at: 4))
            let chunkStart = offset + 8

            if chunkID == "fmt ", chunkSize >= 16 {
                let readCount = Int(min(chunkSize, 16))
                if let formatData = try handle.read(upToCount: readCount), formatData.count >= 12 {
                    byteRate = formatData.littleEndianUInt32(at: 8)
                }
            } else if chunkID == "data" {
                dataSize = chunkSize
            }

            if let byteRate, byteRate > 0, let dataSize {
                return Double(dataSize) / Double(byteRate)
            }

            offset = chunkStart + chunkSize + (chunkSize % 2)
            try handle.seek(toOffset: offset)
        }

        guard let byteRate, byteRate > 0, let dataSize else {
            return nil
        }

        return Double(dataSize) / Double(byteRate)
    }
}

private extension Data {
    func asciiString(in range: Range<Int>) -> String? {
        guard range.lowerBound >= 0, range.upperBound <= count else { return nil }
        return String(data: self[range], encoding: .ascii)
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
