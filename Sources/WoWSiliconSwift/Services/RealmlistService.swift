import Foundation

enum RealmlistResult {
    case none
    case single(url: URL, content: String)
    case multiple([URL])
}

struct RealmlistService {

    private static let ignoredPathComponents = ["Extracted", "extracted"]

    static func find(gamePath: String) -> RealmlistResult {
        let trimmed = gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        let root = URL(fileURLWithPath: trimmed, isDirectory: true)
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

    // MARK: - Helpers

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
