import Foundation

/// Condenses a message by running the user's own Claude Code install, the way Talk2Me does.
///
/// Speek2Me never sees the user's Claude credentials: the user signs in once with
/// `claude auth login`, and Claude Code reads its own login from its config and the Keychain.
public struct ClaudeCodeCondenser: Condenser {
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    /// Print mode with no tools, MCP servers, slash commands or saved session: one text-in, text-out turn.
    /// Hooks are off for this run; its own Stop hook would otherwise become a new announcement.
    public static func arguments(model: ClaudeModel, instructions: String) -> [String] {
        [
            "-p",
            "--model", model.rawValue,
            "--system-prompt", instructions,
            "--tools", "",
            "--strict-mcp-config",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--effort", "low",
            "--output-format", "json",
            "--settings", #"{"disableAllHooks":true}"#,
        ]
    }

    struct PrintResult: Decodable {
        let is_error: Bool?
        let result: String?
        let subtype: String?
    }

    public static func parseOutput(_ data: Data) throws -> String {
        guard let result = try? JSONDecoder().decode(PrintResult.self, from: data) else {
            let raw = String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw CondenserError.claudeCode(raw.isEmpty ? "no output" : raw)
        }
        if result.is_error == true {
            throw CondenserError.claudeCode(result.result ?? result.subtype ?? "unknown error")
        }
        guard let text = result.result else { throw CondenserError.badResponse("missing result") }
        return CondensePrompt.sanitize(text)
    }

    public func condense(_ text: String, project: String, model: ClaudeModel, instructions: String) async throws -> String {
        let output = try await Self.run(
            executable,
            arguments: Self.arguments(model: model, instructions: instructions),
            stdin: CondensePrompt.userMessage(for: text, project: project)
        )
        return try Self.parseOutput(output)
    }

    // MARK: - Install and sign-in status

    /// What the setup guide shows about the user's Claude Code install.
    public struct Status: Sendable, Equatable {
        public var version: String?
        public var loggedIn: Bool
        /// "claude.ai" for a subscription login, otherwise an API key or cloud provider.
        public var authMethod: String?
        /// "pro", "max", … for subscription logins.
        public var subscriptionType: String?

        public init(version: String?, loggedIn: Bool, authMethod: String?, subscriptionType: String?) {
            self.version = version
            self.loggedIn = loggedIn
            self.authMethod = authMethod
            self.subscriptionType = subscriptionType
        }

        /// Whether this install can run `model`; unknown versions are given the benefit of the doubt.
        public func supports(_ model: ClaudeModel) -> Bool {
            guard let version, let minimum = model.minimumClaudeCodeVersion else { return true }
            return ClaudeCodeCondenser.compareVersions(version, minimum) != .orderedAscending
        }
    }

    public static func status(of executable: URL) async -> Status {
        async let versionOutput = try? run(executable, arguments: ["--version"], stdin: "")
        async let authOutput = try? run(executable, arguments: ["auth", "status", "--json"], stdin: "")
        let version = await versionOutput.flatMap { parseVersion(String(decoding: $0, as: UTF8.self)) }
        var status = await authOutput.map(parseAuthStatus) ?? Status(version: nil, loggedIn: false, authMethod: nil, subscriptionType: nil)
        status.version = version
        return status
    }

    /// `claude --version` prints e.g. "2.1.306 (Claude Code)".
    public static func parseVersion(_ output: String) -> String? {
        output.split(whereSeparator: \.isWhitespace).first.map(String.init).flatMap { token in
            token.first?.isNumber == true ? token : nil
        }
    }

    struct AuthStatus: Decodable {
        let loggedIn: Bool?
        let authMethod: String?
        let subscriptionType: String?
    }

    public static func parseAuthStatus(_ data: Data) -> Status {
        let auth = try? JSONDecoder().decode(AuthStatus.self, from: data)
        return Status(version: nil, loggedIn: auth?.loggedIn ?? false,
                      authMethod: auth?.authMethod, subscriptionType: auth?.subscriptionType)
    }

    /// Numeric dotted-version comparison: "2.1.206" < "2.1.280" < "2.10.0".
    public static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let left = a.split(separator: ".").map { Int($0) ?? 0 }
        let right = b.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    // MARK: - Process

    /// Runs `claude` in an empty temporary directory so no project CLAUDE.md is picked up.
    static func run(_ executable: URL, arguments: [String], stdin input: String) async throws -> Data {
        do {
            return try await ProcessRunner.run(
                executable, arguments: arguments, stdin: Data(input.utf8),
                environment: environment(for: executable), workingDirectory: workingDirectory())
        } catch ProcessError.failed(let message) {
            throw CondenserError.claudeCode(message)
        }
    }

    /// `ProcessRunner`'s PATH plus `SPEEK2ME_SUPPRESS`, which tells the hook CLI that this run is ours.
    static func environment(
        for executable: URL,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = ProcessRunner.environment(for: executable, base: base)
        environment["SPEEK2ME_SUPPRESS"] = "1"
        return environment
    }

    static func workingDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speek2me-claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
