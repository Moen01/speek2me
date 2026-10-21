import AppKit
import Combine
import Foundation
import Speek2MeCore

/// Watches the inbox and turns each event into sound: condense, earcon, speak.
@MainActor
final class AnnouncementController: ObservableObject {
    enum Phase {
        case idle, condensing, speaking, needsYou
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastAnnouncement = "Nothing yet"
    @Published private(set) var lastFailure: String?
    /// nil: hook not installed. true: installed and its command exists. false: installed but stale.
    @Published private(set) var hookHealth: [SessionSource: Bool?] = [:]
    @Published private(set) var claudeExecutable: URL?

    private let settings: AppSettings
    private let inbox = Inbox(directory: Inbox.defaultDirectory)
    private var watcher: InboxWatcher?
    private var queue: AnnouncementQueue?
    private let playback = AudioPlayback()
    private let earconPlayback = AudioPlayback()
    private let apple: AppleSpeaker
    private var lastEvent: SessionEvent?
    private var lastText: String?

    init(settings: AppSettings) {
        self.settings = settings
        apple = AppleSpeaker(voiceIdentifier: { [weak settings] in
            let id = settings?.appleVoiceID ?? ""
            return id.isEmpty ? nil : id
        })
    }

    func start() {
        let queue = AnnouncementQueue { [weak self] event in
            await self?.handle(event)
        }
        self.queue = queue
        drain()
        let watcher = InboxWatcher(directory: inbox.directory) { [weak self] in
            Task { @MainActor in self?.drain() }
        }
        do {
            try watcher.start()
        } catch {
            lastFailure = "Cannot watch the inbox: \(error)"
        }
        self.watcher = watcher
        Task { await refreshClaudeExecutable() }
        refreshHookHealth()
    }

    func drain() {
        guard let queue else { return }
        let events = (try? inbox.drain()) ?? []
        for event in events {
            Task { await queue.enqueue(event) }
        }
    }

    /// Used by the setup guide's Try it step and tests of the full path.
    func announce(_ event: SessionEvent) {
        guard let queue else { return }
        Task { await queue.enqueue(event) }
    }

    func stop() {
        Task {
            await queue?.stop()
            await apple.stop()
            playback.stop()
            earconPlayback.stop()
            phase = .idle
        }
    }

    func replay() {
        guard let lastEvent, let lastText else { return }
        Task { await say(lastText, earcon: Earcon.forEvent(lastEvent), needsYou: lastEvent.kind == .needsYou) }
    }

    func speakSample(_ text: String) async {
        lastAnnouncement = text
        await say(text, earcon: .done)
    }

    func refreshClaudeExecutable() async {
        claudeExecutable = await ToolLocator.newestClaude(customPath: settings.claudePath)
    }

    func refreshHookHealth() {
        hookHealth[.claudeCode] = health(of: try? ConfigFile.read(ClaudeHooksInstaller.settingsURL))
        hookHealth[.codex] = health(of: try? ConfigFile.read(CodexHooksInstaller.hooksURL))
    }

    private func health(of data: Data?) -> Bool? {
        guard let commands = try? HooksJSON.installedCommands(data), !commands.isEmpty else { return nil }
        return commands.allSatisfy(HookCommand.isHealthy)
    }

    // MARK: - Pipeline

    private func handle(_ event: SessionEvent) async {
        lastEvent = event
        if settings.muted { return }
        if event.kind == .needsYou, event.reason == .idle, !settings.speakIdle { return }

        let text: String
        if event.kind == .turnComplete {
            phase = .condensing
            let outcome: CondenseOutcome
            if settings.readFull {
                outcome = CondenseOutcome(text: RawCondenser.condense(event.text, maxSentences: 40), condensed: false, failure: nil, duration: .zero)
            } else {
                outcome = await CondenseRouter.run(
                    text: event.text,
                    project: event.project,
                    backend: makeCondenser(),
                    model: settings.model,
                    instructions: CondensePrompt.system(extraInstructions: settings.extraInstructions),
                    timeout: .seconds(settings.timeoutSeconds),
                    maxSentences: settings.maxSentences
                )
            }
            if let failure = outcome.failure { lastFailure = failure }
            text = Announcer.text(for: event, condensed: outcome.text)
        } else {
            text = Announcer.text(for: event, condensed: "")
        }
        lastText = text
        lastAnnouncement = text
        let quiet = settings.quietWhenTerminalFocused && terminalIsFrontmost
        await say(text, earcon: Earcon.forEvent(event), speech: !quiet, needsYou: event.kind == .needsYou)
    }

    private func say(_ text: String, earcon: Earcon, speech: Bool = true, needsYou: Bool = false) async {
        phase = needsYou ? .needsYou : .speaking
        defer { phase = .idle }
        if settings.earcons, let data = try? Data(contentsOf: earcon.fileURL) {
            try? await earconPlayback.play(data)
        }
        guard speech else { return }
        do {
            try await speaker().speak(text)
        } catch is CancellationError {
            // Stopped on purpose.
        } catch {
            lastFailure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The condenser for the current settings; nil means speak the raw message.
    func makeCondenser() -> (any Condenser)? {
        switch settings.condenser {
        case .off:
            return nil
        case .apiKey:
            return AnthropicMessagesCondenser { KeychainStore.read(.anthropic) }
        case .claudeCode:
            guard let claudeExecutable else {
                lastFailure = CondenserError.claudeNotFound.errorDescription
                return nil
            }
            return ClaudeCodeCondenser(executable: claudeExecutable)
        }
    }

    private func speaker() -> any Speaker {
        let hasKey = !(KeychainStore.read(.elevenLabs) ?? "").isEmpty
        let voiceID = settings.voiceID
        let modelID = settings.modelID
        let primary: (any Speaker)? = hasKey
            ? ElevenLabsSpeaker(playback: playback, apiKey: { KeychainStore.read(.elevenLabs) }, voiceID: { voiceID }, modelID: { modelID })
            : nil
        return FallbackSpeaker(primary: primary, fallback: apple) { [weak self] reason in
            Task { @MainActor in self?.lastFailure = reason }
        }
    }

    private var terminalIsFrontmost: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return settings.terminalBundleIDs.contains(bundleID)
    }
}
