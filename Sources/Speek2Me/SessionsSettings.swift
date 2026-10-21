import SwiftUI
import Speek2MeCore

struct SessionsSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AnnouncementController

    var body: some View {
        Form {
            if !Bundle.main.bundleURL.path.hasPrefix("/Applications/") {
                Section {
                    Label("Speek2Me is running from \(Bundle.main.bundleURL.deletingLastPathComponent().path). Move it to Applications before installing hooks, or they break when the app moves.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
            Section("Claude Code") {
                SessionRow(tool: .claudeCode, settings: settings, controller: controller)
            }
            Section("Codex CLI") {
                SessionRow(tool: .codex, settings: settings, controller: controller)
            }
        }
        .formStyle(.grouped)
    }
}

/// One tool: whether it is installed, whether the hook is in place, and the buttons to change that.
struct SessionRow: View {
    let tool: SessionSource
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AnnouncementController

    @State private var executable: URL?
    @State private var version: String?
    @State private var message: String?
    @State private var plannedChange: String?

    private var installed: Bool {
        switch tool {
        case .claudeCode: ClaudeHooksInstaller.isInstalled()
        case .codex: CodexHooksInstaller.isInstalled()
        }
    }

    private var command: String {
        HookCommand.command(bundleURL: Bundle.main.bundleURL, tool: tool == .claudeCode ? "claude" : "codex")
    }

    var body: some View {
        LabeledContent("Tool") {
            if let executable {
                Text("\(executable.path)\(version.map { " (\($0))" } ?? "")").textSelection(.enabled)
            } else {
                Text("not found").foregroundStyle(.secondary)
            }
        }
        .task { await refresh() }
        LabeledContent("Hook") {
            switch controller.hookHealth[tool] ?? nil {
            case nil: Text("not installed").foregroundStyle(.secondary)
            case true?: Label("installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case false?: Label("installed, but its command no longer exists", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        if tool == .codex {
            TextField("Custom codex path (leave empty to search)", text: $settings.codexPath)
        }
        HStack {
            Button("Install") { change(install: true) }
                .disabled(installed && controller.hookHealth[tool] == true)
            Button("Remove", role: .destructive) { change(install: false) }
                .disabled(!installed)
            Button("Show change") { showChange() }
            Spacer()
            Button("Check again") { Task { await refresh() } }
        }
        if let message {
            Text(message).font(.callout).textSelection(.enabled)
        }
        if tool == .codex {
            Text("Codex asks you to trust new hooks once: run /hooks inside Codex after installing. The hook needs features.hooks = true in ~/.codex/config.toml; Install adds it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let plannedChange {
            ScrollView {
                Text(plannedChange).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 180)
        }
    }

    private func refresh() async {
        switch tool {
        case .claudeCode:
            await controller.refreshClaudeExecutable()
            executable = controller.claudeExecutable
        case .codex:
            executable = ToolLocator.codex(customPath: settings.codexPath)
        }
        version = if let executable { await ToolLocator.version(of: executable) } else { nil }
        controller.refreshHookHealth()
    }

    private func change(install: Bool) {
        plannedChange = nil
        do {
            switch (tool, install) {
            case (.claudeCode, true):
                // A stale command is replaced: remove the old entry first.
                if installed { try ClaudeHooksInstaller.remove() }
                let backup = try ClaudeHooksInstaller.install(command: command)
                message = "Installed into \(ClaudeHooksInstaller.settingsURL.path)." + backupNote(backup.map { [$0] } ?? [])
            case (.claudeCode, false):
                let backup = try ClaudeHooksInstaller.remove()
                message = "Removed." + backupNote(backup.map { [$0] } ?? [])
            case (.codex, true):
                if installed { try CodexHooksInstaller.remove() }
                let backups = try CodexHooksInstaller.install(command: command)
                message = "Installed into \(CodexHooksInstaller.hooksURL.path). Now run /hooks inside Codex to trust it." + backupNote(backups)
            case (.codex, false):
                let backup = try CodexHooksInstaller.remove()
                message = "Removed." + backupNote(backup.map { [$0] } ?? [])
            }
        } catch {
            message = "Nothing was changed: \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
        }
        controller.refreshHookHealth()
    }

    private func showChange() {
        do {
            switch tool {
            case .claudeCode:
                plannedChange = "\(ClaudeHooksInstaller.settingsURL.path)\n\n" + (try ClaudeHooksInstaller.plannedChange(command: command))
            case .codex:
                let change = try CodexHooksInstaller.plannedChange(command: command)
                plannedChange = "\(CodexHooksInstaller.hooksURL.path)\n\n\(change.hooks)\n\n\(CodexHooksInstaller.configURL.path)\n\n\(change.config)"
            }
            message = "Key order and formatting change when the file is rewritten; the backup keeps the original."
        } catch {
            message = "Cannot read the current file: \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
        }
    }

    private func backupNote(_ backups: [URL]) -> String {
        backups.isEmpty ? "" : " Backup: " + backups.map(\.lastPathComponent).joined(separator: ", ")
    }
}
