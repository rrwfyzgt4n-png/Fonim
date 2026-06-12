import Foundation

public enum WaveAudioInspector {
    public static func durationSeconds(for url: URL) throws -> Double? {
        let data = try Data(contentsOf: url)
        guard data.count >= 12,
              data.asciiString(in: 0..<4) == "RIFF",
              data.asciiString(in: 8..<12) == "WAVE" else {
            return nil
        }

        var offset = 12
        var byteRate: UInt32?
        var dataSize: UInt32?

        while offset + 8 <= data.count {
            let chunkID = data.asciiString(in: offset..<(offset + 4))
            let chunkSize = Int(data.littleEndianUInt32(at: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + chunkSize

            guard chunkEnd <= data.count else { break }

            if chunkID == "fmt ", chunkSize >= 16 {
                byteRate = data.littleEndianUInt32(at: chunkStart + 8)
            } else if chunkID == "data" {
                dataSize = UInt32(chunkSize)
                break
            }

            offset = chunkEnd + (chunkSize % 2)
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
