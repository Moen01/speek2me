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
            let id = settings?.voice(for: .apple) ?? ""
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

    /// Paused: leave the inbox alone, stop what is playing, forget what was queued. Resumed:
    /// pick up what arrived meanwhile (the drain drops anything older than two minutes).
    func setPaused(_ paused: Bool) {
        if paused { stop() } else { drain() }
    }

    func drain() {
        guard let queue, !settings.muted else { return }
        let events = (try? inbox.drain()) ?? []
        // One task keeps the drained order; one task per event would race the actor hops.
        Task {
            for event in events { await queue.enqueue(event) }
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
        lastFailure = nil
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
        lastFailure = nil
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
            // Stop pressed while condensing: the raw fallback must not be spoken either.
            if Task.isCancelled { return }
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
        // Replay or a voice test while something is playing: the newer announcement wins.
        earconPlayback.stop()
        playback.stop()
        await apple.stop()
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

    /// The selected provider first, the Apple voice when it fails. A provider that is selected
    /// but not set up still goes through the fallback, so the menu says why.
    private func speaker() -> any Speaker {
        let provider = settings.voiceProvider
        let primary: (any Speaker)?
        switch provider {
        case .apple:
            primary = nil
        case .piper:
            let model = (settings.piperModelPath as NSString).expandingTildeInPath
            if let executable = ToolLocator.piper(customPath: settings.piperPath), FileManager.default.fileExists(atPath: model), !settings.piperModelPath.isEmpty {
                primary = PiperSpeaker(executable: executable, model: URL(fileURLWithPath: model), playback: playback)
            } else {
                primary = UnavailableSpeaker(.engine("Piper is not set up. Choose the piper command and a voice model in Settings."))
            }
        default:
            let account = KeychainStore.account(for: provider)
            let config = settings.cloudConfig(for: provider)
            primary = CloudSpeaker(provider: provider, playback: playback,
                                   apiKey: { account.flatMap(KeychainStore.read) }, config: { config })
        }
        return FallbackSpeaker(primary: primary, fallback: apple) { [weak self] reason in
            Task { @MainActor in self?.lastFailure = reason }
        }
    }

    private var terminalIsFrontmost: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return settings.terminalBundleIDs.contains(bundleID)
    }
}
