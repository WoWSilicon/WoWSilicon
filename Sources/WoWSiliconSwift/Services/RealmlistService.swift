import Foundation

enum RealmlistResult {
    case none
    case single(url: URL, content: String)
    case multiple([URL])
}

struct RealmlistServer: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String?
    let address: String
    let isActive: Bool

    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        let host = address
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .split(separator: ".")
            .map(String.init)
        if host.count >= 2, ["logon", "login", "realm"].contains(host[0].lowercased()) {
            return host[1].capitalized
        }
        return address
    }
}

struct RealmlistService {

    private static let ignoredPathComponents = ["Extracted", "extracted"]
    private static let realmlistPattern = try! NSRegularExpression(
        pattern: #"^\s*(#\s*)?set\s+realmlist\s+(.+?)\s*$"#,
        options: [.caseInsensitive]
    )
    private static let namePattern = try! NSRegularExpression(
        pattern: #"^\s*#\s*WoWSilicon:\s*(.*?)\s*$"#,
        options: [.caseInsensitive]
    )

    static func find(gamePath: String) -> RealmlistResult {
        let trimmed = gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        let url = URL(fileURLWithPath: trimmed)
        var isDir: ObjCBool = false
        let root: URL
        if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir) {
            root = isDir.boolValue ? url : url.deletingLastPathComponent()
        } else if url.pathExtension.lowercased() == "exe" {
            root = url.deletingLastPathComponent()
        } else {
            root = url
        }

        let candidates = findCandidates(under: root)

        switch candidates.count {
        case 0:
            return .none
        case 1:
            let url = candidates[0]
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return .single(url: url, content: content)
        default:
            return .multiple(candidates)
        }
    }

    static func write(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func servers(in content: String) -> [RealmlistServer] {
        parsedServers(in: content).map(\.server)
    }

    static func activatingServer(id: Int, in content: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        for parsed in parsedServers(in: content) {
            let prefix = parsed.server.id == id ? "" : "#"
            lines[parsed.server.id] = "\(prefix)set realmlist \(parsed.server.address)"
        }
        return lines.joined(separator: "\n")
    }

    static func addingServer(name: String, address: String, to content: String) -> String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAddress = normalizedAddress(address)
        guard !cleanAddress.isEmpty else { return content }

        var updated = content
        if !updated.isEmpty && !updated.hasSuffix("\n") {
            updated.append("\n")
        }
        if !cleanName.isEmpty {
            updated.append("# WoWSilicon: \(cleanName)\n")
        }
        updated.append("#set realmlist \(cleanAddress)\n")

        guard let added = servers(in: updated).last else { return updated }
        return activatingServer(id: added.id, in: updated)
    }

    static func updatingServer(id: Int, name: String, address: String, in content: String) -> String {
        guard let parsed = parsedServers(in: content).first(where: { $0.server.id == id }) else {
            return content
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAddress = normalizedAddress(address)
        guard !cleanAddress.isEmpty else { return content }

        var lines = content.components(separatedBy: .newlines)
        var serverLine = parsed.server.id
        if let nameLine = parsed.nameLine {
            if cleanName.isEmpty {
                lines.remove(at: nameLine)
                serverLine -= 1
            } else {
                lines[nameLine] = "# WoWSilicon: \(cleanName)"
            }
        } else if !cleanName.isEmpty {
            lines.insert("# WoWSilicon: \(cleanName)", at: serverLine)
            serverLine += 1
        }

        lines[serverLine] = "\(parsed.server.isActive ? "" : "#")set realmlist \(cleanAddress)"
        return lines.joined(separator: "\n")
    }

    static func removingServer(id: Int, from content: String) -> String {
        guard let parsed = parsedServers(in: content).first(where: { $0.server.id == id }) else {
            return content
        }

        var lines = content.components(separatedBy: .newlines)
        lines.remove(at: parsed.server.id)
        if let nameLine = parsed.nameLine {
            lines.remove(at: nameLine)
        }

        var updated = lines.joined(separator: "\n")
        let remaining = servers(in: updated)
        if parsed.server.isActive, !remaining.isEmpty, !remaining.contains(where: \.isActive) {
            updated = activatingServer(id: remaining[0].id, in: updated)
        }
        return updated
    }

    static func currentRealmValue(gamePath: String) -> String? {
        guard case .single(_, let content) = find(gamePath: gamePath) else { return nil }
        return extractRealmValue(from: content)
    }

    // MARK: - Helpers

    private struct ParsedServer {
        let server: RealmlistServer
        let nameLine: Int?
    }

    private static func parsedServers(in content: String) -> [ParsedServer] {
        let lines = content.components(separatedBy: .newlines)
        var result: [ParsedServer] = []

        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = realmlistPattern.firstMatch(in: line, range: range),
                  let addressRange = Range(match.range(at: 2), in: line) else {
                continue
            }

            let address = normalizedAddress(String(line[addressRange]))
            guard !address.isEmpty else { continue }

            var name: String?
            var nameLine: Int?
            if index > 0 {
                let previous = lines[index - 1]
                let previousRange = NSRange(previous.startIndex..<previous.endIndex, in: previous)
                if let nameMatch = namePattern.firstMatch(in: previous, range: previousRange),
                   let valueRange = Range(nameMatch.range(at: 1), in: previous) {
                    let value = String(previous[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        name = value
                        nameLine = index - 1
                    }
                }
            }

            result.append(
                ParsedServer(
                    server: RealmlistServer(
                        id: index,
                        name: name,
                        address: address,
                        isActive: match.range(at: 1).location == NSNotFound
                    ),
                    nameLine: nameLine
                )
            )
        }
        return result
    }

    private static func normalizedAddress(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func extractRealmValue(from content: String) -> String? {
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = trimmed.lowercased()
            guard lowercased.hasPrefix("set realmlist") else { continue }

            let remainder = trimmed.dropFirst("set realmlist".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return remainder.isEmpty ? nil : String(remainder)
        }
        return nil
    }

    private static func findCandidates(under root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let components = url.pathComponents
            if components.contains(where: { ignoredPathComponents.contains($0) }) {
                if url.hasDirectoryPath { enumerator.skipDescendants() }
                continue
            }
            if url.lastPathComponent.lowercased() == "realmlist.wtf" {
                results.append(url)
            }
        }
        return results
    }
}
