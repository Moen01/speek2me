# Speek2Me design

Date: 2026-10-21. Status: draft for approval.

## Intent

Speek2Me is a macOS menu-bar app that speaks to you about your terminal AI
sessions. When Claude Code or Codex CLI finishes a turn, it reads the final
answer aloud, condensed. When a session needs you (permission prompt,
question, idle nudge), it says so with a distinct cue. Streaming output,
thinking and tool chatter stay silent.

It is the sibling of Talk2Me. Talk2Me turns your speech into text for the
machine. Speek2Me turns the machine's final words into speech for you.

Why: long agent tasks run while you are in another window or another room.
Today a shell hook (`~/.claude/hooks/cmux-notify.sh`) flashes the terminal and
has a muted `say` call. A spoken, condensed answer lets you decide from the
hallway whether to come back.

## Goals

- Speak the final assistant message at the end of every main-thread turn in
  Claude Code and Codex CLI.
- Speak when a session waits on you: permission prompt, question or
  elicitation, idle nudge. Each kind has its own earcon.
- Say which project is talking when several sessions run.
- Never go silent: if the cloud voice fails, use the on-device Apple voice. If
  condensing fails, speak the raw text, trimmed.
- One-click, additive, reversible hook install from the setup guide.
- Reuse Talk2Me's Claude backend choice (Claude Code CLI with your own login,
  API key, or Off) and its step-list setup guide.

## Non-goals (v1)

- ChatGPT desktop or web sessions. No hook API exists; scraping is brittle.
- Replying by voice. Talk2Me covers input.
- Reading streaming output or subagent chatter.
- Windows, Linux, iOS.
- Auto-release workflow and in-app updates. Copy from Talk2Me in v1.1.

## Anti-goals

- Slowing or blocking a session. Hooks run async, exit 0, print nothing.
- Overwriting other hooks (the cmux notifier must keep working).
- Sending text anywhere except the backends the user chose. Off mode keeps
  everything on the machine.
- Storing secrets outside the Keychain.

## Constraints

- Same stack as Talk2Me: Swift 6.2, SwiftPM, macOS 26, Apple silicon, no Xcode
  project. App target in Swift 5 language mode for AppKit callbacks, Core
  target in Swift 6 mode.
- No third-party Swift packages. URLSession for ElevenLabs and Anthropic,
  AVFoundation for playback and Apple speech. Flag it if one becomes necessary.
- Hook commands inherit no shell PATH and no tty. Use absolute paths.
- Config edits: additive, idempotent, backed up, atomic.

## Verified facts the design rests on

Claude Code 2.1.306 (installed here), from the hooks reference:

- `Stop` fires when Claude finishes responding. Stdin JSON carries
  `last_assistant_message` (final text), `session_id`, `cwd`,
  `transcript_path`, `stop_hook_active`, `hook_event_name`. Inside a subagent
  the payload also carries `agent_id` and `agent_type`.
- `Notification` stdin carries `message`, `title`, `notification_type`. The
  matcher is the type string. Types used here: `permission_prompt`,
  `elicitation_dialog`, `elicitation_url_dialog`, `agent_needs_input`,
  `idle_prompt` (about 60 s after a turn with no input). Others are ignored.
- Hook entry: `{"type":"command","command":"...","timeout":5,"async":true}`.
  `async` never blocks Claude. Exit 0 with no stdout changes nothing.
  `Notification` ignores exit codes entirely.
- User hooks live in `~/.claude/settings.json` under `hooks.<Event>[]`, each
  item `{matcher, hooks:[...]}`. Existing entries there today: `Stop` and
  `Notification` both run `cmux-notify.sh`.
- `claude -p --settings '{"disableAllHooks":true}'` runs a one-shot turn with
  all hooks off. This is the recursion guard when the app itself calls Claude.
- `transcript_path` lags. Do not read it; use `last_assistant_message`.

Codex CLI, from the hooks guide (not installed on this Mac; unverified live):

- Hooks use the same three-level JSON schema (event, matcher group, handlers)
  in `~/.codex/hooks.json`, or inline `[hooks]` in `~/.codex/config.toml`.
  They need `features.hooks = true` in `config.toml`, and the user must trust
  them once with `/hooks` inside Codex.
- `Stop` stdin carries `last_assistant_message` (string or null), `turn_id`,
  `session_id`, `cwd`. `PermissionRequest` carries `tool_name` and
  `tool_input.description`. `SubagentStop` exists; not registered.
- Exit 0 with no output is success. Older `notify = [...]` setting still
  exists; not used, so an existing `notify` keeps working.

ElevenLabs API: `POST /v1/text-to-speech/{voice_id}` with header `xi-api-key`,
body `{text, model_id}`, returns audio. `GET /v1/voices` lists voices.

## Architecture

SwiftPM targets:

- `Speek2MeCore`: no UI. Event model, hook payload parsers, inbox, condenser
  backends, speakers, queue, config patchers.
- `Speek2Me`: menu-bar app. Settings, setup guide, directory watcher, status.
- `speek2me-hook`: tiny CLI the hooks run. Bundled inside the app at
  `Contents/MacOS/speek2me-hook`.
- `Speek2MeCoreTests`.

### Event flow

1. A hook fires and runs `speek2me-hook claude` or `speek2me-hook codex`. The
   CLI reads stdin JSON, normalizes it to a `SessionEvent`, writes it as one
   JSON file into the inbox `~/Library/Application Support/Speek2Me/inbox/`
   (write to a temp name, then rename), exits 0. Target: under 50 ms. It
   never prints to stdout. Unparsable input or an unknown event: write
   nothing, exit 0. If env `SPEEK2ME_SUPPRESS=1` is set: exit 0 immediately.
2. The app watches the inbox directory (DispatchSource on the directory
   descriptor). New file: read, delete, enqueue.
3. The announcer builds the spoken text. `turnComplete`: condense the message
   (see Condenser), prefix with the project name. `needsYou`: fixed template
   from the reason and message. Example: "rea: done. Report ready, Chrome
   stopped." / "rea needs you: permission to run git push."
4. The speaker plays an earcon for the kind, then speaks. ElevenLabs first,
   Apple on failure. One utterance at a time.
5. The menu-bar icon shows idle, speaking or needs-you. Menu: last
   announcement text, Replay, Stop, Mute, Settings…, Setup Guide…, Quit.

### SessionEvent

Codable. `source` (claudeCode, codex), `kind` (turnComplete, needsYou),
`reason` (permission, question, idle, none), `text`, `sessionID`, `project`
(last path component of `cwd`), `cwd`, `receivedAt`, `agentID` (nil on the
main thread).

Mapping rules, applied in the hook CLI:

- Claude `Stop` with `agent_id` present: ignore (subagent).
- Claude `Stop` main thread: `turnComplete`, text = `last_assistant_message`.
  Empty or missing text: ignore.
- Claude `Notification`: `permission_prompt` to needsYou/permission;
  `elicitation_dialog`, `elicitation_url_dialog`, `agent_needs_input` to
  needsYou/question; `idle_prompt` to needsYou/idle; every other type ignored.
- Codex `Stop`: `turnComplete` from `last_assistant_message`; null: ignore.
- Codex `PermissionRequest`: needsYou/permission, text from `tool_name` and
  `tool_input.description`.

### Condenser

Mirrors Talk2Me's `CleanupBackend`. Protocol `Condenser`:
`condense(_ text: String, project: String) async throws -> String`.

- `ClaudeCodeCondenser`: spawns the user's `claude` with Talk2Me's print-mode
  arguments (`-p`, `--model`, `--system-prompt`, `--tools ""`,
  `--strict-mcp-config`, `--disable-slash-commands`,
  `--no-session-persistence`, `--effort low`, `--output-format json`) plus
  `--settings '{"disableAllHooks":true}'` and env `SPEEK2ME_SUPPRESS=1`.
  Locates `claude` the way Talk2Me does, with a custom path setting. Reads
  `claude auth status --json` for the setup guide.
- `AnthropicMessagesCondenser`: `POST /v1/messages` with the Keychain key.
  Same wire code as Talk2Me.
- `RawCondenser` (Off): strips markdown, code blocks, URLs and paths, keeps
  the first N sentences (setting, default 3).
- Prompt (builder tunes wording): you are the voice of a coding assistant;
  turn the final message into at most three spoken sentences; lead with the
  outcome; say plainly if the user must do something; no markdown, no code,
  no file paths, say "a file in src" instead; keep numbers that matter.
- Timeout (default 15 s) or any error: fall back to `RawCondenser`. The
  announcement is never dropped.
- Default model: Haiku 5.5 (my call: this is a pager; speed beats polish).
  Picker offers Opus, Sonnet, Haiku like Talk2Me.

### Speaker

Protocol `Speaker`: `speak(_ text: String) async throws`, `stop()`.

- `ElevenLabsSpeaker`: `POST /v1/text-to-speech/{voiceID}` with
  `output_format=mp3_44100_128`, `model_id` default `eleven_flash_v2_5`
  (builder may pick a newer low-latency model), 10 s timeout, play the
  returned MP3 with AVAudioPlayer. Errors map to a typed enum: missing key,
  invalid key (401), quota or rate limit (429), HTTP, timeout. Voice list via
  `GET /v1/voices`, cached per key for the picker.
- `AppleSpeaker`: AVSpeechSynthesizer, voice chosen in settings, system
  default otherwise.
- Policy: no ElevenLabs key: Apple. ElevenLabs error or timeout: Apple with
  the same text, and the menu shows why. Earcons come from system sounds in
  `/System/Library/Sounds` (done, permission, question, idle), toggle to
  disable.

### Queue

Serial. Same session, two unspoken events: keep the newest. Stop cancels the
current utterance and empties the queue. On app launch, inbox files older than
two minutes are discarded; newer ones are coalesced per session and spoken.

### Quiet rules

- Mute toggle in the menu.
- "Quiet while the terminal is in front" (default off): skip speech, keep the
  earcon, when the frontmost app is in a small editable list (Terminal,
  iTerm2, Ghostty, cmux, Warp, kitty, WezTerm, Alacritty).
- "Speak idle nudges" (default on).

### Config patching

Shared `ConfigPatcher` rules: read, parse, detect our entry by a command path
containing `speek2me-hook`; present: no change; absent: append; write a backup
`<file>.bak-speek2me-<ISO timestamp>` next to the original; write atomically.
Invalid existing file: refuse, show the error, change nothing.

- Claude Code: `~/.claude/settings.json`. Append one handler to
  `hooks.Stop[0].hooks` and a new matcher group under `hooks.Notification`
  with matcher
  `permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input|idle_prompt`.
  Handler: `{"type":"command","command":"<app>/Contents/MacOS/speek2me-hook claude","timeout":5,"async":true}`.
  Foundation re-serializes the JSON, so key order and formatting change; the
  backup keeps the original. Said plainly in the UI before Install.
- Codex: `~/.codex/hooks.json` gets `Stop` and `PermissionRequest` groups with
  `speek2me-hook codex`. `~/.codex/config.toml` gets `hooks = true` under
  `[features]`: add the line if the table exists, append the table if not,
  touch nothing else. Setup guide then tells the user to run `/hooks` in
  Codex once to trust it.
- Remove reverses both, with the same backup rule.
- Hook path is the running bundle's path. If the app is not in
  `/Applications`, the Sessions step warns first, like Talk2Me's install flow.
  On every launch the app checks the installed command paths still exist and
  shows a repair hint in the menu if not.

### Settings

Tabs: Voice (ElevenLabs key with Test, voice picker, Apple fallback voice,
earcons), Claude (backend, model, timeout, custom path, extra instructions),
Sessions (Claude Code and Codex rows: found or not, version, hook installed
or not, Install, Remove, Show change), Behaviour (condense or read full,
sentence cap, quiet rules, idle nudges), About.

### Setup guide

Same shape as Talk2Me's `OnboardingView`: sidebar with live step status,
steps Welcome, Voice, Claude, Sessions, Try it, Ready. Try it sends a sample
`Stop` payload through the installed hook command end to end, so what you
hear is the real path. The Voice step states which text leaves the machine:
the spoken summary to ElevenLabs, the full final message to Anthropic unless
Off.

### Packaging

Copy Talk2Me's `scripts/build-app.sh`, `make-icon.sh`, `next-version.sh`,
`package-release.sh`, `Resources/Info.plist` (`LSUIElement`), entitlements
(no sandbox, network client, no microphone). Signing identity "Speek2Me
Signing". Add the hook CLI to `Contents/MacOS`.

## Tests

Core, same test style as Talk2Me:

- Payload parsers: fixtures for Claude `Stop` (main thread, subagent,
  empty text), each `Notification` type, Codex `Stop` (text, null),
  `PermissionRequest`, malformed JSON, unknown event. Each gives the exact
  `SessionEvent` or nil.
- Hook CLI: writes one file atomically, exits 0, prints nothing; with
  `SPEEK2ME_SUPPRESS=1` writes nothing.
- Inbox: write, watch, read, delete round trip; stale file discard.
- `ConfigPatcher`: missing file, empty object, existing cmux hooks preserved,
  already installed is a no-op, backup created, invalid JSON refuses without
  writing, remove restores shape. TOML `features.hooks` cases: no table,
  table without key, key already true.
- Condenser: Claude Code argument list includes the hook-disable setting and
  the env var; output parsing; raw fallback on error and timeout; raw
  condenser strips markdown and caps sentences.
- Speaker policy: fake ElevenLabs failing falls through to a fake Apple
  speaker with the same text; missing key skips ElevenLabs.
- Queue: same-session coalescing, stop clears, order kept across sessions.

## Decisions I made (not from the user)

- ElevenLabs as the primary voice, Apple as fallback.
- Condense by default, Haiku 5.5, three sentences; "read full" is a setting.
- Inbox directory plus directory watcher instead of a socket: durable when
  the app is not running, trivially testable, no port.
- Idle nudges spoken by default.
- Project name is the last component of `cwd`.
- One hook CLI for both tools; Codex via hooks, not the older `notify`.
- Repo name kept as typed: `speek2me`, app name `Speek2Me`.

## Answered by the user

- Name stays `speek2me`; app name `Speek2Me`.
- GitHub: create `Moen01/speek2me` and push when there is something to push;
  then keep pushing as work lands.

## Left to the builder

UI copy and layout, app icon, exact earcon files, default ElevenLabs voice
and model id, prompt wording, directory-watch implementation, the list of
`codex` install locations to probe, and test fixture contents.
