import AppKit
import AVFoundation
import SwiftUI
import Speek2MeCore

/// The first-run setup guide: voice, Claude, hooks for each tool, and a test announcement.
/// The sidebar shows which steps are done, so you can jump to whatever still needs you.
struct OnboardingView: View {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome, voice, claude, sessions, tryIt, ready

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .voice: "Voice"
            case .claude: "Connect Claude"
            case .sessions: "Sessions"
            case .tryIt: "Try it"
            case .ready: "Ready"
            }
        }

        var symbol: String {
            switch self {
            case .welcome: "hand.wave"
            case .voice: "speaker.wave.2"
            case .claude: "sparkles"
            case .sessions: "terminal"
            case .tryIt: "waveform"
            case .ready: "checkmark.seal"
            }
        }
    }

    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AnnouncementController
    let finish: () -> Void

    @State private var step: Step = .welcome
    @StateObject private var setup = SetupStatus()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    Group {
                        switch step {
                        case .welcome: WelcomeStep()
                        case .voice: VoiceStep(settings: settings, controller: controller, setup: setup)
                        case .claude: ConnectClaudeStep(settings: settings, controller: controller, setup: setup)
                        case .sessions: SessionsStep(settings: settings, controller: controller, setup: setup)
                        case .tryIt: TryItStep(controller: controller, setup: setup)
                        case .ready: ReadyStep(settings: settings, setup: setup) { step = $0 }
                        }
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                Divider()
                footer
            }
        }
        .frame(width: 780, height: 600)
        .task { await setup.refresh(settings: settings, controller: controller) }
    }

    // MARK: Frame

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("Set up Speek2Me").font(.headline)
            }
            .padding(.bottom, 14)
            ForEach(Step.allCases) { item in
                Button { step = item } label: {
                    HStack(spacing: 8) {
                        StepStatusIcon(state: setup.state(of: item, settings: settings), symbol: item.symbol)
                        Text(item.title)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(step == item ? Color.accentColor.opacity(0.18) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Open this again from the menu-bar icon: Setup Guide…")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(.background.secondary)
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { move(-1) }
            }
            Spacer()
            Button {
                Task { await setup.refresh(settings: settings, controller: controller) }
            } label: {
                Label(setup.checking ? "Checking…" : "Check Again", systemImage: "arrow.clockwise")
            }
            .disabled(setup.checking)
            .help("Check every step again, after you changed something in Terminal")
            if step == .ready {
                Button("Start Using Speek2Me", action: finish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Skip Setup", action: finish)
                Button(step == .welcome ? "Get Started" : "Next") { move(1) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(16)
    }

    private func move(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        step = next
    }
}

// MARK: - Status

/// What is already in place, shared by the sidebar, the steps and the summary.
@MainActor
final class SetupStatus: ObservableObject {
    enum State { case done, attention, optional, none }

    /// nil until the Test voice button was used; false when the provider failed and Apple spoke instead.
    @Published var voiceTested: Bool?
    // Read once and after a save: the Keychain is too slow to ask on every redraw.
    @Published var apiKeySaved = KeychainStore.read(.anthropic) != nil
    @Published private(set) var claude: ClaudeCodeCondenser.Status?
    @Published private(set) var claudeHooks = ClaudeHooksInstaller.isInstalled()
    @Published private(set) var codex: URL?
    @Published private(set) var codexHooks = CodexHooksInstaller.isInstalled()
    @Published private(set) var checking = false
    @Published var heard = false

    func refresh(settings: AppSettings, controller: AnnouncementController) async {
        checking = true
        defer { checking = false }
        apiKeySaved = KeychainStore.read(.anthropic) != nil
        await controller.refreshClaudeExecutable()
        claude = if let executable = controller.claudeExecutable { await ClaudeCodeCondenser.status(of: executable) } else { nil }
        codex = ToolLocator.codex(customPath: settings.codexPath)
        refreshHooks(controller: controller)
    }

    func refreshHooks(controller: AnnouncementController) {
        claudeHooks = ClaudeHooksInstaller.isInstalled()
        codexHooks = CodexHooksInstaller.isInstalled()
        controller.refreshHookHealth()
    }

    /// Whether the chosen provider has what it needs: a key, or the Piper files, or nothing for Apple.
    func voiceConfigured(_ settings: AppSettings) -> Bool {
        switch settings.voiceProvider {
        case .apple:
            return true
        case .piper:
            let model = (settings.piperModelPath as NSString).expandingTildeInPath
            return ToolLocator.piper(customPath: settings.piperPath) != nil && !settings.piperModelPath.isEmpty && FileManager.default.fileExists(atPath: model)
        default:
            return KeychainStore.account(for: settings.voiceProvider).flatMap(KeychainStore.read) != nil
        }
    }

    func claudeReady(_ settings: AppSettings) -> Bool {
        switch settings.condenser {
        case .off: false
        case .apiKey: apiKeySaved
        case .claudeCode: claude.map { $0.loggedIn && $0.supports(settings.model) } ?? false
        }
    }

    func state(of step: OnboardingView.Step, settings: AppSettings) -> State {
        switch step {
        case .welcome, .ready: .none
        case .voice: !voiceConfigured(settings) || voiceTested == false ? .attention : .done
        case .claude: settings.condenser == .off ? .optional : claudeReady(settings) ? .done : .attention
        case .sessions: claudeHooks ? .done : .attention
        case .tryIt: heard ? .done : .optional
        }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            StepHeader(symbol: "speaker.wave.2", title: "Welcome to Speek2Me",
                       subtitle: "Your AI sessions speak up when they finish, and when they need you.")
            VStack(alignment: .leading, spacing: 18) {
                FeatureRow(symbol: "checkmark.bubble", title: "Hear the ending, not the typing",
                           text: "When Claude Code or Codex finishes a turn, you hear the answer in a few sentences. Streaming output and tool chatter stay silent.")
                FeatureRow(symbol: "exclamationmark.bubble", title: "Know when you're needed",
                           text: "A permission prompt, a question or an idle nudge gets its own sound and words, with the project's name first.")
                FeatureRow(symbol: "lock.shield", title: "Only what you choose leaves this Mac",
                           text: "ElevenLabs gets the spoken sentences, Claude gets the final message to condense. Turn either off and nothing is sent.")
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
    }
}

private struct VoiceStep: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AnnouncementController
    @ObservedObject var setup: SetupStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeader(symbol: "speaker.wave.2", title: "Pick a voice",
                       subtitle: "Cloud voices sound best and need a key. Apple and Piper run on this Mac. Whatever you pick, the Apple voice steps in if it fails.")
            Card {
                VoiceProviderCard(settings: settings, controller: controller) { ok in
                    setup.voiceTested = ok
                }
            }
            .frame(maxWidth: 560)
            Toggle("Short sound before each announcement", isOn: $settings.earcons)
        }
        .onChange(of: settings.voiceProvider) { setup.voiceTested = nil }
    }
}

private struct ConnectClaudeStep: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AnnouncementController
    @ObservedObject var setup: SetupStatus

    @State private var checking = false
    @State private var apiKeyDraft = ""
    @State private var testResult: (ok: Bool, text: String)?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeader(symbol: "sparkles", title: "Connect Claude",
                       subtitle: "Claude turns a long final message into a few spoken sentences. Pick how Speek2Me reaches it.")
            Picker("", selection: $settings.condenser) {
                Text("Claude subscription").tag(CondenserKind.claudeCode)
                Text("API key").tag(CondenserKind.apiKey)
                Text("Skip for now").tag(CondenserKind.off)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            Card {
                switch settings.condenser {
                case .claudeCode: subscriptionCard
                case .apiKey: apiKeyCard
                case .off:
                    Label("You'll hear the first few sentences of each message, read as they are. You can connect Claude any time in Settings.",
                          systemImage: "text.alignleft")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 480)

            if settings.condenser != .off {
                HStack {
                    Picker("Model", selection: $settings.model) {
                        ForEach(ClaudeModel.allCases) { Text($0.displayName).tag($0) }
                    }
                    .frame(maxWidth: 280)
                    Button(testing ? "Testing…" : "Test connection") { Task { await test() } }
                        .disabled(testing)
                }
                if let testResult {
                    Label(testResult.text, systemImage: testResult.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(testResult.ok ? .green : .orange)
                        .font(.callout)
                        .frame(maxWidth: 480, alignment: .leading)
                        .lineLimit(4)
                }
            }
        }
        .task(id: settings.condenser) {
            testResult = nil
            if settings.condenser == .claudeCode { await refreshStatus() }
        }
        .onChange(of: settings.model) { testResult = nil }
    }

    @ViewBuilder private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let claudePath = controller.claudeExecutable {
                if checking {
                    HStack { ProgressView().controlSize(.small); Text("Checking Claude Code…") }
                } else if let status = setup.claude, status.loggedIn {
                    Label(signedInText(status), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                    Text("Claude Code \(status.version ?? "") at \(claudePath.path)").font(.caption).foregroundStyle(.secondary)
                    if !status.supports(settings.model) {
                        Label("\(settings.model.displayName) needs Claude Code \(settings.model.minimumClaudeCodeVersion ?? "") or newer.",
                              systemImage: "arrow.up.circle")
                            .foregroundStyle(.orange)
                        Button("Update Claude Code") {
                            TerminalCommand.run("'\(claudePath.path)' update", name: "update")
                        }
                    }
                } else {
                    Label("Claude Code isn't signed in yet", systemImage: "person.crop.circle.badge.questionmark")
                        .font(.headline)
                    Text("Sign in once with your Claude account. A Terminal window opens for it.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Sign In…") { TerminalCommand.run("'\(claudePath.path)' auth login", name: "sign-in") }
                            .buttonStyle(.borderedProminent)
                        Button("Check Again") { Task { await refreshStatus() } }
                    }
                }
            } else {
                Label("Claude Code isn't installed", systemImage: "shippingbox")
                    .font(.headline)
                Text("Install Claude Code, then sign in with your Claude account.")
                    .foregroundStyle(.secondary)
                HStack {
                    Link("Get Claude Code", destination: URL(string: "https://claude.com/product/claude-code")!)
                    Button("Check Again") { Task { await refreshStatus() } }
                }
            }
            Text("Speek2Me runs your own Claude Code with hooks turned off, so its own turns are never announced, and never sees your login.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SecureField(setup.apiKeySaved ? "Saved in your Keychain" : "Paste your key (sk-ant-…)", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty, KeychainStore.save(.anthropic, key) else { return }
                    apiKeyDraft = ""
                    setup.apiKeySaved = true
                }
                .disabled(apiKeyDraft.isEmpty)
            }
            if setup.apiKeySaved {
                Label("Key saved in your Keychain", systemImage: "key.fill")
                    .foregroundStyle(.green)
            }
            HStack(spacing: 4) {
                Text("Usage is billed to your key.")
                Link("Get an API key", destination: URL(string: "https://platform.claude.com/settings/keys")!)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signedInText(_ status: ClaudeCodeCondenser.Status) -> String {
        if status.authMethod == "claude.ai", let plan = status.subscriptionType {
            return "Signed in · Claude \(plan.capitalized) plan"
        }
        return "Signed in"
    }

    private func refreshStatus() async {
        checking = true
        await setup.refresh(settings: settings, controller: controller)
        checking = false
    }

    private func test() async {
        testing = true
        defer { testing = false }
        let outcome = await CondenseRouter.run(
            text: "## Done\n\nI fixed the failing test in `src/queue.ts` and the suite passes: 67 green. The push to origin is waiting for your approval.",
            project: "demo",
            backend: controller.makeCondenser(),
            model: settings.model,
            instructions: CondensePrompt.system(extraInstructions: settings.extraInstructions),
            timeout: .seconds(max(settings.timeoutSeconds, 30)),
            maxSentences: settings.maxSentences
        )
        let seconds = Double(outcome.duration.components.seconds) + Double(outcome.duration.components.attoseconds) / 1e18
        testResult = outcome.condensed
            ? (true, String(format: "Connected in %.1f s: ", seconds) + outcome.text)
            : (false, outcome.failure ?? "No answer from Claude.")
    }
}

private struct SessionsStep: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AnnouncementController
    @ObservedObject var setup: SetupStatus

    @State private var message: String?
    @State private var shown: String?

    private var inApplications: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeader(symbol: "terminal", title: "Connect your sessions",
                       subtitle: "Each tool gets a small hook that tells Speek2Me when a turn ends or you are needed. Nothing else changes.")
            if !inApplications {
                Label("Speek2Me is running from \(Bundle.main.bundleURL.deletingLastPathComponent().path). Move it to Applications first, or the hooks break when the app moves.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .frame(maxWidth: 500, alignment: .leading)
            }
            VStack(spacing: 10) {
                SetupRow(ok: setup.claudeHooks, title: "Claude Code",
                         detail: setup.claudeHooks
                             ? "Hook installed in ~/.claude/settings.json."
                             : "Adds a Stop and a Notification hook to ~/.claude/settings.json. Other hooks stay as they are; a backup is kept.") {
                    if !setup.claudeHooks {
                        Button("Install") { install(.claudeCode) }.buttonStyle(.borderedProminent)
                    }
                    Button("Show change") { show(.claudeCode) }
                }
                SetupRow(ok: setup.codex == nil ? nil : setup.codexHooks, title: "Codex CLI",
                         detail: setup.codex == nil
                             ? "Codex CLI was not found on this Mac. Optional; install it later and come back here."
                             : setup.codexHooks
                                 ? "Hook installed in ~/.codex/hooks.json. Run /hooks inside Codex once to trust it."
                                 : "Adds a Stop and a PermissionRequest hook to ~/.codex/hooks.json and turns hooks on in config.toml. Codex then asks you once, with /hooks, to trust it.") {
                    if setup.codex != nil, !setup.codexHooks {
                        Button("Install") { install(.codex) }.buttonStyle(.borderedProminent)
                    }
                    if setup.codex != nil {
                        Button("Show change") { show(.codex) }
                    }
                }
            }
            .frame(maxWidth: 520)
            if let message {
                Text(message).font(.callout).textSelection(.enabled).frame(maxWidth: 520, alignment: .leading)
            }
            if let shown {
                ScrollView {
                    Text(shown).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 520, maxHeight: 160)
                .padding(8)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func command(_ tool: SessionSource) -> String {
        HookCommand.command(bundleURL: Bundle.main.bundleURL, tool: tool == .claudeCode ? "claude" : "codex")
    }

    private func install(_ tool: SessionSource) {
        shown = nil
        do {
            switch tool {
            case .claudeCode:
                let backup = try ClaudeHooksInstaller.install(command: command(tool))
                message = "Installed." + (backup.map { " Backup: \($0.lastPathComponent)" } ?? "")
            case .codex:
                let backups = try CodexHooksInstaller.install(command: command(tool))
                message = "Installed. Now run /hooks inside Codex to trust it." + (backups.isEmpty ? "" : " Backups: " + backups.map(\.lastPathComponent).joined(separator: ", "))
            }
        } catch {
            message = "Nothing was changed: \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
        }
        setup.refreshHooks(controller: controller)
    }

    private func show(_ tool: SessionSource) {
        do {
            switch tool {
            case .claudeCode:
                shown = "\(ClaudeHooksInstaller.settingsURL.path)\n\n" + (try ClaudeHooksInstaller.plannedChange(command: command(tool)))
            case .codex:
                let change = try CodexHooksInstaller.plannedChange(command: command(tool))
                shown = "\(CodexHooksInstaller.hooksURL.path)\n\n\(change.hooks)\n\n\(CodexHooksInstaller.configURL.path)\n\n\(change.config)"
            }
            message = "Key order and formatting change when the file is rewritten; the backup keeps the original."
        } catch {
            message = "Cannot read the current file: \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
        }
    }
}

private struct TryItStep: View {
    @ObservedObject var controller: AnnouncementController
    @ObservedObject var setup: SetupStatus

    @State private var sent = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(symbol: "waveform", title: "Try it",
                       subtitle: "Sends a pretend end-of-turn through the same hook command Claude Code will use, so what you hear is the real path.")
            HStack {
                Button("Send a test turn") { send() }
                    .buttonStyle(.borderedProminent)
                if sent {
                    Button("Heard it") { setup.heard = true }
                    Button("Try again") { send() }
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            }
            Label(statusText, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480, alignment: .leading)
                .lineLimit(3)
            if setup.heard {
                Label("Great, you're connected.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    private var statusText: String {
        switch controller.phase {
        case .idle: "Last: \(controller.lastAnnouncement)"
        case .condensing: "Condensing with Claude…"
        case .speaking: "Speaking…"
        case .needsYou: "Announcing that a session needs you…"
        }
    }

    /// Runs the installed hook command (or the bundled CLI when none is installed) with a sample Stop payload.
    private func send() {
        error = nil
        let installed = (try? HooksJSON.installedCommands(ConfigFile.read(ClaudeHooksInstaller.settingsURL)))?.first
        let path = installed.flatMap(HookCommand.executablePath(in:)) ?? HookCommand.executableURL(bundleURL: Bundle.main.bundleURL).path
        let cwd = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/demo").path
        let payload = """
        {"hook_event_name":"Stop","session_id":"setup-guide","cwd":"\(cwd)","last_assistant_message":"All done. I fixed the failing test and the suite is green, 67 passing. Nothing else is needed from you."}
        """
        sent = true
        // Off the main actor: the hook is quick, but a broken command must not freeze the window.
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["claude"]
            let stdin = Pipe()
            process.standardInput = stdin
            do {
                try process.run()
                // write(contentsOf:) throws on a closed pipe instead of raising an exception.
                try? stdin.fileHandleForWriting.write(contentsOf: Data(payload.utf8))
                try? stdin.fileHandleForWriting.close()
                process.waitUntilExit()
            } catch {
                let text = "Could not run \(path): \(error.localizedDescription)"
                await MainActor.run { self.error = text }
            }
        }
    }
}

private struct ReadyStep: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var setup: SetupStatus
    let go: (OnboardingView.Step) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeader(symbol: "checkmark.seal", title: "You're set",
                       subtitle: "Speek2Me lives in your menu bar. Start a session and walk away.")
            VStack(spacing: 10) {
                SetupRow(ok: setup.voiceConfigured(settings) && setup.voiceTested != false, title: "Voice",
                         detail: voiceDetail) {
                    Button("Change…") { go(.voice) }
                }
                SetupRow(ok: settings.condenser == .off ? nil : setup.claudeReady(settings), title: "Claude",
                         detail: claudeDetail) {
                    if !setup.claudeReady(settings) { Button(settings.condenser == .off ? "Connect…" : "Fix…") { go(.claude) } }
                }
                SetupRow(ok: setup.claudeHooks, title: "Sessions",
                         detail: setup.claudeHooks
                             ? "Claude Code hook installed." + (setup.codexHooks ? " Codex hook installed." : "")
                             : "No hook installed yet; nothing will be announced.") {
                    if !setup.claudeHooks { Button("Install…") { go(.sessions) } }
                }
                SetupRow(ok: setup.heard ? true : nil, title: "Test",
                         detail: setup.heard ? "You heard a test announcement." : "Optional: send one test turn before you start.") {
                    if !setup.heard { Button("Try It…") { go(.tryIt) } }
                }
            }
            .frame(maxWidth: 500)
        }
    }

    private var voiceDetail: String {
        let name = settings.voiceProvider.displayName
        if !setup.voiceConfigured(settings) { return "\(name) is selected but not set up; the Apple voice will speak instead." }
        if setup.voiceTested == false { return "\(name) failed its test; the Apple voice spoke instead." }
        return settings.voiceProvider == .apple ? "Apple voice." : "\(name), with the Apple voice as fallback."
    }

    private var claudeDetail: String {
        switch settings.condenser {
        case .off: "Off: the first sentences are read as they are. Optional."
        case .apiKey: setup.apiKeySaved ? "Using your API key with \(settings.model.displayName)." : "No API key saved yet."
        case .claudeCode:
            setup.claudeReady(settings)
                ? "Using your Claude subscription with \(settings.model.displayName)."
                : "Claude Code is not installed, not signed in, or too old for \(settings.model.displayName)."
        }
    }
}

// MARK: - Building blocks

/// One thing to have in place: done (true), needs you (false) or optional (nil), with its fix beside it.
private struct SetupRow<Actions: View>: View {
    let ok: Bool?
    let title: String
    let detail: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            StepStatusIcon(state: ok == true ? .done : ok == false ? .attention : .optional, symbol: "circle")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct StepStatusIcon: View {
    let state: SetupStatus.State
    let symbol: String

    var body: some View {
        switch state {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .attention: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .optional: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        case .none: Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
        }
    }
}

private struct StepHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 22, weight: .bold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.teal)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
