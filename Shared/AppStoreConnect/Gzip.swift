import Foundation

/// Decodes the single-member gzip files App Store Connect uses for reports.
enum Gzip {
    static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
            throw failure("not a gzip stream")
        }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard index + 2 <= bytes.count else { throw failure("truncated header") }
            index += 2 + (Int(bytes[index]) | Int(bytes[index + 1]) << 8)
        }
        if flags & 0x08 != 0 { index = try skipZeroTerminated(bytes, from: index) } // FNAME
        if flags & 0x10 != 0 { index = try skipZeroTerminated(bytes, from: index) } // FCOMMENT
        if flags & 0x02 != 0 { index += 2 } // FHCRC
        let trailerStart = bytes.count - 8
        guard index <= trailerStart else { throw failure("truncated stream") }

        let expectedCRC = littleEndianUInt32(bytes, at: trailerStart)
        let expectedSize = littleEndianUInt32(bytes, at: trailerStart + 4)
        let output: Data
        do {
            // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), which is what gzip wraps.
            output = try (Data(bytes[index..<trailerStart]) as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw failure("the compressed data is corrupt")
        }
        guard UInt32(truncatingIfNeeded: output.count) == expectedSize, CRC32.checksum(output) == expectedCRC else {
            throw failure("checksum mismatch")
        }
        return output
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
        guard let end = bytes[start...].firstIndex(of: 0) else { throw failure("truncated header") }
        return end + 1
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
    }

    private static func failure(_ reason: String) -> BinnacleError {
        .invalidResponse(service: AppStoreConnectClient.serviceName, message: "could not unzip the report (\(reason))")
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value -> UInt32 in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = crc & 1 != 0 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
