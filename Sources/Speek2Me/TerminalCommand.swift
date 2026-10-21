import AppKit

/// Opens a Terminal window running one command, for steps that need the user's own Terminal
/// (signing in to Claude Code, trusting hooks in Codex).
enum TerminalCommand {
    static func run(_ command: String, name: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speek2me-\(name).command")
        let script = """
        #!/bin/zsh
        clear
        \(command)
        echo
        echo "Done. You can close this window and go back to Speek2Me."
        """
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }
}
