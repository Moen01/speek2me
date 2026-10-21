import Foundation

/// Finds `claude` and `codex` without a shell PATH: a menu-bar app does not inherit one.
public enum ToolLocator {
    public static var claudeCandidates: [URL] {
        executables(named: "claude", in: [
            "/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin", "~/.claude/local", "~/.npm-global/bin",
        ])
    }

    public static var codexCandidates: [URL] {
        executables(named: "codex", in: [
            "/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin", "~/.npm-global/bin", "~/.cargo/bin", "~/.codex/bin",
        ])
    }

    /// The custom path when it is executable, else the first candidate found. Fast; no process runs.
    public static func claude(customPath: String?) -> URL? {
        custom(customPath) ?? claudeCandidates.first
    }

    public static func codex(customPath: String?) -> URL? {
        custom(customPath) ?? codexCandidates.first
    }

    /// The custom path when set, else the candidate reporting the highest `--version`.
    /// This Mac has 2.1.179 from Homebrew and 2.1.306 from nvm; newest wins.
    public static func newestClaude(customPath: String?) async -> URL? {
        if let custom = custom(customPath) { return custom }
        return await newest(among: claudeCandidates)
    }

    public static func newest(among candidates: [URL]) async -> URL? {
        let versions = await withTaskGroup(of: (Int, String?).self, returning: [(Int, String?)].self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask { (index, await version(of: candidate)) }
            }
            var results: [(Int, String?)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }
        }
        var best: (index: Int, version: String)?
        for (index, version) in versions {
            guard let version else { continue }
            if let current = best, ClaudeCodeCondenser.compareVersions(version, current.version) != .orderedDescending { continue }
            best = (index, version)
        }
        return best.map { candidates[$0.index] } ?? candidates.first
    }

    /// The first dotted number in `--version` output: "2.1.306 (Claude Code)" or "codex-cli 0.115.0".
    public static func version(of executable: URL) async -> String? {
        guard let output = try? await ClaudeCodeCondenser.run(executable, arguments: ["--version"], stdin: "") else { return nil }
        return parseVersion(String(decoding: output, as: UTF8.self))
    }

    public static func parseVersion(_ output: String) -> String? {
        output.firstMatch(of: #/\d+(?:\.\d+)+/#).map { String($0.output) }
    }

    // MARK: - Helpers

    private static func custom(_ path: String?) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespaces), !path.isEmpty else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        return FileManager.default.isExecutableFile(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
    }

    /// Fixed directories first, then every nvm Node version, newest first.
    private static func executables(named name: String, in directories: [String]) -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var paths = directories.map { ($0 as NSString).expandingTildeInPath + "/" + name }
        let nvm = "\(home)/.nvm/versions/node"
        let versions = ((try? fm.contentsOfDirectory(atPath: nvm)) ?? []).sorted {
            ClaudeCodeCondenser.compareVersions($0.replacingOccurrences(of: "v", with: ""), $1.replacingOccurrences(of: "v", with: "")) == .orderedDescending
        }
        paths += versions.map { "\(nvm)/\($0)/bin/\(name)" }
        return paths.filter(fm.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}
