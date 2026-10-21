import Foundation
import Testing
@testable import Speek2MeCore

/// Runs ClaudeCodeCondenser against fake `claude` scripts to check the process plumbing.
struct ClaudeCodeCondenserTests {
    private func fakeClaude(_ body: String) throws -> (script: URL, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speek2me-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("claude")
        try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script, dir)
    }

    @Test func argumentsDisableHooksAndEnvironmentSuppresses() {
        let args = ClaudeCodeCondenser.arguments(model: .haiku, instructions: "S")
        #expect(args.first == "-p")
        #expect(args.contains("--settings"))
        #expect(args.contains(#"{"disableAllHooks":true}"#))
        #expect(args.contains("claude-haiku-5-5"))
        let env = ClaudeCodeCondenser.environment(for: URL(fileURLWithPath: "/opt/nvm/bin/claude"), base: ["PATH": "/usr/bin:/bin", "HOME": "/h"])
        #expect(env["SPEEK2ME_SUPPRESS"] == "1")
        #expect(env["PATH"]?.hasPrefix("/opt/nvm/bin:") == true)
        #expect(env["HOME"] == "/h")
    }

    @Test func sendsMessageOnStdinAndReadsResult() async throws {
        // Echo the wrapped message back, minus the tags, to prove it arrived on stdin.
        let (script, dir) = try fakeClaude("""
        input=$(cat | sed -e 's/<[^>]*>//g' | tr -d '\\n')
        printf '{"is_error":false,"result":"%s"}' "$input"
        """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = try await ClaudeCodeCondenser(executable: script).condense("hello", project: "rea", model: .haiku, instructions: "x")
        #expect(text == "hello")
    }

    @Test func nonZeroExitWithoutOutputReportsStderr() async throws {
        let (script, dir) = try fakeClaude("cat > /dev/null\necho 'not logged in' >&2\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: CondenserError.claudeCode("not logged in\n")) {
            try await ClaudeCodeCondenser(executable: script).condense("hi", project: "p", model: .haiku, instructions: "x")
        }
    }

    @Test func parseOutputReportsErrorResults() {
        #expect(throws: CondenserError.claudeCode("boom")) {
            try ClaudeCodeCondenser.parseOutput(Data(#"{"is_error":true,"result":"boom"}"#.utf8))
        }
        #expect(try ClaudeCodeCondenser.parseOutput(Data(#"{"is_error":false,"result":" Done. "}"#.utf8)) == "Done.")
    }

    @Test func parsesVersionAndCompares() {
        #expect(ClaudeCodeCondenser.parseVersion("2.1.306 (Claude Code)") == "2.1.306")
        #expect(ClaudeCodeCondenser.compareVersions("2.1.179", "2.1.306") == .orderedAscending)
        #expect(ClaudeCodeCondenser.compareVersions("2.10.0", "2.9.9") == .orderedDescending)
    }
}
