import Foundation

/// The one TOML edit Speek2Me makes: `hooks = true` under `[features]` in Codex's config.toml.
/// Line-based on purpose; no TOML parser, nothing else in the file is touched.
public enum TOMLFeatures {
    public static func hooksEnabled(in text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        guard let range = featuresTable(in: lines) else { return false }
        return lines[range].contains { line in
            line.firstMatch(of: #/^\s*hooks\s*=\s*true\s*(#.*)?$/#) != nil
        }
    }

    public static func enableHooks(in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let range = featuresTable(in: lines) else {
            var result = text
            if !result.isEmpty, !result.hasSuffix("\n") { result += "\n" }
            if !result.isEmpty { result += "\n" }
            return result + "[features]\nhooks = true\n"
        }
        if let index = lines[range].firstIndex(where: { $0.firstMatch(of: #/^\s*hooks\s*=/#) != nil }) {
            lines[index] = "hooks = true"
        } else {
            lines.insert("hooks = true", at: range.lowerBound)
        }
        return lines.joined(separator: "\n")
    }

    /// The lines after the `[features]` header up to the next table header.
    private static func featuresTable(in lines: [String]) -> Range<Int>? {
        guard let header = lines.firstIndex(where: { $0.firstMatch(of: #/^\s*\[features\]\s*(#.*)?$/#) != nil }) else { return nil }
        let start = header + 1
        let end = lines[start...].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        return start..<end
    }
}
