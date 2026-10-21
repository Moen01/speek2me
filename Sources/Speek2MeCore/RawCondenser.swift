import Foundation

/// The no-model fallback: strips what cannot be spoken and keeps the first sentences.
public enum RawCondenser {
    public static func condense(_ text: String, maxSentences: Int) -> String {
        var lines: [String] = []
        for rawLine in removeCodeFences(text).components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var isHeading = false
            if let heading = line.firstMatch(of: #/^#{1,6}\s+/#) {
                line.removeSubrange(heading.range)
                isHeading = true
            }
            if let marker = line.firstMatch(of: #/^(?:[-*+]|\d+[.)]|>)\s+/#) {
                line.removeSubrange(marker.range)
            }
            line = replaceLinksAndPaths(stripEmphasis(line)).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // A heading has no full stop; give it one so it does not run into the next line.
            if isHeading, let last = line.last, !".!?:".contains(last) { line += "." }
            lines.append(line)
        }
        let joined = lines.joined(separator: " ").replacing(#/\s+/#, with: " ")
        return splitSentences(joined).prefix(max(0, maxSentences)).joined(separator: " ")
    }

    static func removeCodeFences(_ text: String) -> String {
        var result = text.replacing(#/(?s)```.*?```/#, with: " ")
        // An unterminated fence: drop everything after it.
        if let open = result.range(of: "```") { result = String(result[..<open.lowerBound]) }
        return result
    }

    static func stripEmphasis(_ line: String) -> String {
        var result = line
        for marker in ["**", "__", "~~", "`"] { result = result.replacingOccurrences(of: marker, with: "") }
        // Lone * or _ at a word edge is emphasis; inside a word (snake_case) it stays.
        // NSRegularExpression: Swift Regex has no lookbehind.
        let range = NSRange(result.startIndex..., in: result)
        return emphasisEdges.stringByReplacingMatches(in: result, range: range, withTemplate: "")
    }

    private static let emphasisEdges = try! NSRegularExpression(pattern: #"(?<!\w)[*_]+(?=\w)|(?<=\w)[*_]+(?!\w)"#)

    /// URLs become "a link" and absolute or relative paths become "a file"; trailing punctuation stays.
    static func replaceLinksAndPaths(_ line: String) -> String {
        line.split(separator: " ", omittingEmptySubsequences: true).map { token -> String in
            guard let parts = token.firstMatch(of: #/^([\(\["']*)(.*?)([\)\]"',.;:!?]*)$/#) else { return String(token) }
            let (lead, core, trail) = (String(parts.1), String(parts.2), String(parts.3))
            if core.contains("://") { return lead + "a link" + trail }
            if ["/", "~/", "./", "../"].contains(where: core.hasPrefix) { return lead + "a file" + trail }
            return String(token)
        }.joined(separator: " ")
    }

    /// Splits on . ! ? followed by whitespace or the end, so "2.5 seconds" and "app.ts" stay whole.
    static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let atEnd = index + 1 == characters.count
            if ".!?".contains(character), atEnd || characters[index + 1].isWhitespace {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { sentences.append(rest) }
        return sentences
    }
}
