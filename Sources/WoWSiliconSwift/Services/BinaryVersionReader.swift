import Foundation

enum BinaryVersionReader {
    static let versionOffset: UInt64 = 0x437c04
    static let buildOffset: UInt64 = 0x40a364

    /// Reads a null-terminated ASCII string from a given offset in a file.
    static func readString(at offset: UInt64, from url: URL, maxLength: Int = 32) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? fileHandle.close()
        }

        do {
            try fileHandle.seek(toOffset: offset)
            guard let data = try fileHandle.read(upToCount: maxLength) else {
                return nil
            }

            // Find the null terminator
            if let nullIndex = data.firstIndex(of: 0) {
                let subData = data[..<nullIndex]
                return String(data: subData, encoding: .ascii)
            } else {
                return String(data: data, encoding: .ascii)
            }
        } catch {
            return nil
        }
    }

    /// Reads the WoW version string (e.g. "1.18.1") from a binary.
    static func readWoWVersion(from url: URL) -> String? {
        return readString(at: versionOffset, from: url)
    }

    /// Reads the WoW build string (e.g. "Build 5875") from a binary.
    static func readWoWBuild(from url: URL) -> String? {
        // Build strings are longer, but we'll trim or search if needed.
        // For simple comparison, just reading the first part is often enough.
        return readString(at: buildOffset, from: url, maxLength: 128)
    }
}
