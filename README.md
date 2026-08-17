# Quill

Quill is a local-first macOS meeting notes system. It records your microphone
and only the configured call processes, transcribes both sides on-device, and
writes a plain Markdown note with a summary, decisions, action items, and open
questions. There are no accounts, bots, telemetry, cloud APIs, or runtime
network calls.

Quill never starts a recording by itself. When a configured app has live audio
input and output for several seconds, Quill asks **Record / Not now**. You can
also start and stop from the menu bar or CLI. Declining suppresses further
prompts until that call ends.

## Requirements

- macOS 15 or later
- Swift 6 / Xcode 16 or later to build
- Apple Silicon recommended for local transcription
- A pre-downloaded Parakeet model for transcription
- Optional: `llama.cpp` plus a local GGUF instruct model for structured notes

## Build and install

```sh
swift test
swift build -c release
sudo cp .build/release/quill /usr/local/bin/quill

# This is Quill's only network-capable runtime command. Run it intentionally.
quill models download-transcription

# Optional background menu-bar daemon.
quill install --launch-at-login
```

Run `quill doctor` before the first real meeting. Permissions live at:

- System Settings → Privacy & Security → Microphone
- System Settings → Privacy & Security → Screen & System Audio Recording
- System Settings → Privacy & Security → Calendars (optional)

Calendar denial never blocks recording; Quill falls back to the call app and
timestamp for the title.

## What gets captured

Quill resolves configured bundle IDs to Core Audio process object IDs and
constructs a non-global process tap. Output from other processes—Spotify,
Messages notification sounds, and unrelated apps—is excluded. Microphone audio
is a separate track, which yields reliable `me` / `them` transcript labels.

Defaults cover:

- Zoom: `us.zoom.xos`
- Microsoft Teams: `com.microsoft.teams2`, `com.microsoft.teams`
- Slack huddles: `com.tinyspeck.slackmacgap`
- FaceTime: `com.apple.FaceTime`
- Discord: `com.hnc.Discord`
- Webex: `com.cisco.webexmeetingsapp`, `Cisco-Systems.Spark`
- Google Meet and browser huddles: Chrome, Safari, Edge, and Firefox

Core Audio isolates processes, not tabs. If a browser routes multiple tabs
through the same audio process, macOS does not expose a public API that can
separate those tabs; use a dedicated browser window/profile during a recorded
meeting when tab isolation matters.

For an unknown app, find its bundle ID and explicitly select it:

```sh
quill apps
quill start --bundle-id com.example.call --title "Customer interview"
quill stop
```

## Output

The default root is `~/Recordings`. Every meeting is an Obsidian-safe,
chronologically sortable folder:

```text
2026-08-17 1430 - Product weekly/
├── mic.caf
├── system.caf
├── meta.json
├── transcript.json
├── transcript.md
├── note.md
└── transcribe.log
```

- `mic.caf`: your microphone, incrementally written AAC in a crash-tolerant CAF
- `system.caf`: only the selected call processes, incrementally written
- `meta.json`: versioned schema, state, calendar context, app, attendees, times,
  track files, and alignment offsets
- `transcript.json`: completion marker and canonical timed segments
- `transcript.md`: readable speaker-tagged transcript
- `note.md`: summary, decisions, action items, and open questions
- `transcribe.log`: local processing diagnostics

At recording start, `meta.json` is atomically written with `state: recording`.
On a clean stop it becomes `state: complete`. If Quill is force-quit, the next
launch marks the session `interrupted`, preserves the existing audio, and
queues it for transcription. A configurable free-space reserve is checked
before capture begins.

## Local models

Transcription uses FluidAudio's on-device Parakeet TDT 0.6B v2 model. Normal
recording and transcription never download it. If it is absent, processing
fails visibly with instructions to run the explicit model command:

```sh
quill models download-transcription
```

Summarization is behind the `MeetingSummarizer` protocol. The included backend
executes a configured local `llama.cpp` binary and GGUF model. Quill never
downloads a summarization model and never falls back to a network service. If
the backend is absent or fails, `transcript.md` is still written and `note.md`
states exactly why structured notes were not generated.

## Configuration

Create `~/.config/quill/config.json`:

```json
{
  "recordings_dir": "~/Recordings",
  "call_apps": [
    "us.zoom.xos",
    "com.microsoft.teams2",
    "com.tinyspeck.slackmacgap",
    "com.apple.FaceTime",
    "com.hnc.Discord",
    "com.cisco.webexmeetingsapp",
    "Cisco-Systems.Spark",
    "com.google.Chrome",
    "com.apple.Safari",
    "com.microsoft.edgemac",
    "org.mozilla.firefox"
  ],
  "call_prompt_delay_seconds": 8,
  "call_end_delay_seconds": 10,
  "minimum_free_disk_gb": 2,
  "mic_voice_processing": false,
  "transcription": {
    "enabled": true,
    "engine": "parakeet"
  },
  "summarization": {
    "backend": "llama.cpp",
    "executable": "/opt/homebrew/bin/llama-cli",
    "model_path": "~/Models/local-instruct.gguf",
    "prediction_tokens": 1200
  }
}
```

Omit `summarization` to keep transcripts without AI notes. Setting
`transcription.enabled` to `false` keeps audio and metadata only. Replacing
`call_apps` changes both prompt detection and default manual capture targets.

## CLI

```sh
quill run [--out <dir>]                 # menu-bar daemon + call prompts
quill start [--bundle-id <id>] [--title <text>]
quill stop
quill quit
quill open [--out <dir>]
quill apps                              # active audio process bundle IDs
quill transcribe <meeting-dir>          # transcript + structured note
quill note <meeting-dir>                # regenerate note.md locally
quill recover [--out <dir>]             # repair interrupted sessions
quill doctor
quill models download-transcription [--force]
quill install --launch-at-login
quill install --uninstall
```

`start`, `stop`, and `quit` send local distributed notifications to the running
daemon. They do not contact a server. `start --bundle-id` is the manual path for
an unknown call app.

## Development and verification

```sh
sh scripts/check-no-runtime-network.sh
swift test
swift build -c release
```

Pure tests cover process selection, call prompt state, calendar matching,
filename generation, config parsing, folder layout, recovery scanning, disk
policy, model-output parsing, and note formatting. Core Audio and EventKit
still require hands-on testing on a real Mac; follow [MANUAL-TEST.md](MANUAL-TEST.md)
and do not infer hardware success from unit tests.

## Design constraints

- Swift + SPM only; no Electron, Python, or Node runtime
- Plain files only; no database
- No accounts, cloud transcription, cloud summaries, meeting bots, analytics,
  crash reporting, or update checks
- The only network-capable runtime path is the explicit transcription-model
  download subcommand, guarded by CI
