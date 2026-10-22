# Speek2Me

Your terminal AI sessions speak up when they finish, and when they need you.

Speek2Me is a small macOS menu-bar app. When Claude Code or Codex CLI finishes a turn, it reads
the final answer aloud, condensed to a few sentences. When a session is waiting on you (a
permission prompt, a question, an idle nudge), it says so, with the project's name first.
Streaming output, thinking and tool chatter stay silent.

It is the sibling of [Talk2Me](https://github.com/Moen01/talk2me): Talk2Me turns your speech
into text for the machine, Speek2Me turns the machine's final words into speech for you.

## How it works

1. Each tool gets a hook. Claude Code runs it on `Stop` and on `Notification`
   (`permission_prompt`, `elicitation_dialog`, `elicitation_url_dialog`, `agent_needs_input`,
   `idle_prompt`). Codex runs it on `Stop` and `PermissionRequest`. The hook is the bundled
   `speek2me-hook` command: it reads the hook's JSON, drops one small file into
   `~/Library/Application Support/Speek2Me/inbox/`, and exits. It never prints, never blocks,
   and ignores subagent turns and headless `claude -p` runs from temporary folders (such as
   Talk2Me's own cleanup turns).
2. The app watches the inbox. A finished turn is condensed by Claude into at most three spoken
   sentences: by your own Claude Code install (signed in with `claude auth login`, run with
   hooks off so it never announces itself), by a Claude API key, or not at all (the first
   sentences are read as they are).
3. A short system sound tells you the kind of event, then the voice speaks. Pick the provider in
   Settings › Voice; the Apple voice steps in whenever the provider fails, so an announcement is
   never lost.

## Voice providers

| Provider | Needs | Default voice |
| --- | --- | --- |
| ElevenLabs | API key | Rachel, `eleven_flash_v2_5` |
| Apple (on this Mac) | nothing; download **Alex** (English) or **Henrik** (Norwegian) in System Settings › Accessibility › Spoken Content › Manage Voices for a much better one | system voice |
| OpenAI | API key | `marin`, `gpt-4o-mini-tts` |
| Google Cloud Text-to-Speech | API key with the Text-to-Speech API enabled | `en-US-Chirp3-HD-Aoede` |
| Azure Speech | Speech resource key and region | `en-US-JennyNeural`, region `norwayeast` |
| Deepgram Aura | API key | `aura-2-thalia-en` |
| Cartesia Sonic | API key | Cartesia's docs voice, `sonic-3.6` |
| Piper (local) | `pip install piper-tts` and a voice `.onnx` + `.onnx.json` | your model |

Every cloud provider is called over HTTPS with the key from the Keychain and returns MP3; all of
them have unit tests for the request shape. Only ElevenLabs and Apple have been exercised against
the real service so far.

Several sessions at once are fine: each announcement starts with the project folder's name, and
a newer event from the same session replaces one you have not heard yet.

## Install

Requires macOS 26 or later on an Apple silicon Mac. Download **Speek2Me.zip** from the
[latest release](https://github.com/Moen01/speek2me/releases/latest) (once the repository is
public), or build from source:

```sh
./scripts/build-app.sh
cp -R build/Speek2Me.app /Applications/
open /Applications/Speek2Me.app
```

The setup guide opens on first launch: pick a voice, connect Claude, install the hooks, send a
test turn. Reopen it any time from the menu-bar icon with **Setup Guide…**.

## What the hooks change, and how to undo it

- **Claude Code**: one handler is appended to `hooks.Stop` and one matcher group to
  `hooks.Notification` in `~/.claude/settings.json`. Existing hooks are kept. The file is
  rewritten by a JSON serializer, so key order and formatting change; a backup named
  `settings.json.bak-speek2me-<timestamp>` is written beside it first. **Settings › Sessions ›
  Show change** displays the exact result before you click Install, and **Remove** takes the
  handlers out again, with another backup.
- **Codex CLI**: `Stop` and `PermissionRequest` handlers go into `~/.codex/hooks.json`, and
  `hooks = true` is added under `[features]` in `~/.codex/config.toml`. Codex asks you once, with
  `/hooks`, to trust the new hook. Remove takes the handlers out; the `features` line stays.
  Codex support was built from the Codex docs and session files; it has not been exercised
  against a live Codex CLI yet.

## Privacy

- With a cloud voice provider set up, the spoken sentences are sent to that provider and billed to your key.
- With a Claude backend on, the full final message is sent to Claude (through your Claude Code
  subscription or your API key) to be condensed.
- With Claude off and Apple or Piper as the voice, nothing leaves this Mac.
- Keys are stored in the macOS Keychain. The inbox files hold only the event text and are
  deleted as soon as they are read.

## Updates

Settings › About shows the installed version and checks GitHub for a newer release each time it
opens; **Check for Updates…** in the menu goes there too. Update downloads the release zip,
verifies it against the release's SHA256SUMS and the Speek2Me signing certificate, swaps the app
bundle and relaunches. Every push to `main` that changes more than docs publishes a release
through `.github/workflows/release.yml`, signed with the same certificate from the repository
secrets `SIGNING_CERT_P12` and `SIGNING_CERT_PASSWORD`.

## Pause

**Pause announcements** in the menu, or ⌃⌥⌘M from any app, stops everything: nothing is read
from the inbox, nothing is sent to Claude, nothing is spoken, and whatever is playing stops. The
same shortcut resumes; events that arrived in the last two minutes are then announced, older
ones are dropped. The shortcut can be turned off in Settings › Behaviour.

## Menu

Replay the last announcement, Stop the current one, Pause, and Settings for the voice, the Claude
backend, the hooks and the quiet rules (read the whole message, sentence cap, stay quiet while a
terminal is in front, speak idle nudges).

## Build from source

Needs Xcode 26 (Swift 6.2).

```sh
swift test
./scripts/build-app.sh
open build/Speek2Me.app
```

Design and plan live in `docs/superpowers/`.
