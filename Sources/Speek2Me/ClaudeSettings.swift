import SwiftUI
import Speek2MeCore

struct ClaudeSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AnnouncementController

    @State private var apiKeyDraft = ""
    @State private var apiKeySaved = KeychainStore.read(.anthropic) != nil
    @State private var status: ClaudeCodeCondenser.Status?
    @State private var testOutput = ""
    @State private var testing = false

    private let sample = """
    ## Done

    I refactored `src/queue.ts` and `/Users/moen/project/src/worker.ts`, added 4 tests, and ran the suite: 67 passing. \
    One thing needs you: the push to `origin/main` is waiting for your approval.
    """

    var body: some View {
        Form {
            Section("Condense with Claude") {
                Picker("Backend", selection: $settings.condenser) {
                    ForEach(CondenserKind.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Model", selection: $settings.model) {
                    ForEach(ClaudeModel.allCases) { Text($0.displayName).tag($0) }
                }
                .disabled(settings.condenser == .off)
                Stepper(value: $settings.timeoutSeconds, in: 5...60, step: 1) {
                    Text("Give up after \(Int(settings.timeoutSeconds)) s and speak the raw message")
                }
                TextField("Extra instructions (optional)", text: $settings.extraInstructions, axis: .vertical)
                    .lineLimit(2...5)
            }

            if settings.condenser == .claudeCode {
                Section("Claude Code") {
                    LabeledContent("Using", value: controller.claudeExecutable?.path ?? "not found")
                    if let status {
                        LabeledContent("Status", value: statusText(status))
                    }
                    TextField("Custom path (leave empty to use the newest install found)", text: $settings.claudePath)
                    Text("Sign in once in Terminal with `claude auth login`. Speek2Me never sees your Claude login; it runs your own Claude Code with hooks turned off, so its own turns are never announced.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.condenser == .apiKey {
                Section("Claude API key") {
                    SecureField(apiKeySaved ? "Saved in the Keychain" : "sk-ant-…", text: $apiKeyDraft)
                    HStack {
                        Button("Save key") {
                            let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !key.isEmpty, KeychainStore.save(.anthropic, key) else { return }
                            apiKeyDraft = ""
                            apiKeySaved = true
                        }
                        .disabled(apiKeyDraft.isEmpty)
                        Button("Remove key", role: .destructive) {
                            KeychainStore.delete(.anthropic)
                            apiKeySaved = false
                        }
                        .disabled(!apiKeySaved)
                    }
                    Text("Create a key at platform.claude.com. Usage is billed to that key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Try it") {
                Button(testing ? "Condensing…" : "Condense a sample message") { Task { await runTest() } }
                    .disabled(testing)
                if !testOutput.isEmpty {
                    Text(testOutput).textSelection(.enabled).font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .task(id: controller.claudeExecutable) {
            guard let executable = controller.claudeExecutable else { status = nil; return }
            status = await ClaudeCodeCondenser.status(of: executable)
        }
    }

    private func statusText(_ status: ClaudeCodeCondenser.Status) -> String {
        var parts: [String] = []
        if let version = status.version { parts.append("version \(version)") }
        parts.append(status.loggedIn ? "signed in" + (status.subscriptionType.map { " (\($0))" } ?? "") : "not signed in")
        return parts.joined(separator: ", ")
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        let outcome = await CondenseRouter.run(
            text: sample,
            project: "demo",
            backend: controller.makeCondenser(),
            model: settings.model,
            instructions: CondensePrompt.system(extraInstructions: settings.extraInstructions),
            timeout: .seconds(settings.timeoutSeconds),
            maxSentences: settings.maxSentences
        )
        let seconds = Double(outcome.duration.components.seconds) + Double(outcome.duration.components.attoseconds) / 1e18
        testOutput = outcome.condensed
            ? String(format: "%.1f s: ", seconds) + outcome.text
            : "Raw fallback\(outcome.failure.map { " (\($0))" } ?? ""): \(outcome.text)"
    }
}
