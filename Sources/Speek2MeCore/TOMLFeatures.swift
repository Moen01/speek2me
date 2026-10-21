import Foundation

/// The one TOML edit Speek2Me makes: `hooks = true` under `[features]` in Codex's config.toml.
/// Line-based on purpose; no TOML parser, nothing else in the file is touched. Handles the two
/// spellings TOML allows: a `[features]` table, or a dotted `features.hooks = …` key at the root.
public enum TOMLFeatures {
    public static func hooksEnabled(in text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        if let range = featuresTable(in: lines),
           lines[range].contains(where: { $0.firstMatch(of: #/^\s*hooks\s*=\s*true\s*(#.*)?$/#) != nil }) {
            return true
        }
        return rootLines(in: lines).contains { $0.firstMatch(of: #/^\s*features\.hooks\s*=\s*true\s*(#.*)?$/#) != nil }
    }

    public static func enableHooks(in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if let range = featuresTable(in: lines) {
            if let index = lines[range].firstIndex(where: { $0.firstMatch(of: #/^\s*hooks\s*=/#) != nil }) {
                lines[index] = "hooks = true"
            } else {
                lines.insert("hooks = true", at: range.lowerBound)
            }
            return lines.joined(separator: "\n")
        }
        let root = rootLines(in: lines)
        if let index = root.firstIndex(where: { $0.firstMatch(of: #/^\s*features\.hooks\s*=/#) != nil }) {
            lines[index] = "features.hooks = true"
            return lines.joined(separator: "\n")
        }
        // Other dotted `features.` keys at the root already define the table; a `[features]` header
        // after them would be a redefinition, which TOML rejects. Add one more dotted key beside them.
        if let last = root.lastIndex(where: { $0.firstMatch(of: #/^\s*features\./#) != nil }) {
            lines.insert("features.hooks = true", at: last + 1)
            return lines.joined(separator: "\n")
        }
        var result = text
        if !result.isEmpty, !result.hasSuffix("\n") { result += "\n" }
        if !result.isEmpty { result += "\n" }
        return result + "[features]\nhooks = true\n"
    }

    /// The lines after the `[features]` header up to the next table header.
    private static func featuresTable(in lines: [String]) -> Range<Int>? {
        guard let header = lines.firstIndex(where: { $0.firstMatch(of: #/^\s*\[features\]\s*(#.*)?$/#) != nil }) else { return nil }
        let start = header + 1
        let end = lines[start...].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        return start..<end
    }

    /// The lines before the first table header, where dotted root keys live.
    private static func rootLines(in lines: [String]) -> ArraySlice<String> {
        let end = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        return lines[0..<end]
    }
}
