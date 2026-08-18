# Changelog

## 0.2.7

- Added Kimi K3 and Kimi K3 Fast as immediately available Venice choices, so
  selecting them never depends on the remote model catalog loading first.
- Connected explicit Generate summary and Regenerate summary actions to the
  configured AI provider and model, while keeping automatic processing local.
- Replaced the sentence-stitching fallback for user-requested AI summaries
  with structured provider analysis that rejects invented decisions, owners,
  due dates, and action items.
- Reused the same hardened remote request path for Ask Scribe and summaries,
  with Keychain credentials, optional contact redaction, and clear errors.

## 0.2.6

- Added true microphone-only recording for in-person meetings; manual online
  recordings now infer the active call app when possible.
- Stopped treating missing legacy source metadata as “In person,” and added a
  safe source-label correction path for older recordings.
- Added visible Generate summary and Regenerate summary actions to every
  meeting, including transcript-only recordings from older releases.
- Let API keys save to Keychain before a model is selected, with clear saved
  confirmation and save failures that remain visible.
- Reduced model-catalog waits to eight seconds and added a verified Venice
  fallback list so a temporary catalog outage cannot block setup.

## 0.2.5

- Made Venice model discovery use its fast public text-model catalog first,
  with authenticated retry if Venice requires it.
- Added a 12-second model-list timeout and a visible Cancel action so provider
  setup can never remain on an indefinite spinner.

## 0.2.4

- Restored the standard macOS Edit menu so Paste and the usual text-editing
  shortcuts work in API keys, Ask Scribe, search, rename, notes, and Settings.
- Corrected responder-chain targets for system-owned Hide and Close commands.

## 0.2.3

- Replaced manual AI model-name setup with an account-aware, searchable model
  picker for Venice AI, OpenAI, Claude, Grok/xAI, and custom compatible APIs.
- Added provider-specific model discovery, sensible default selection, refresh,
  clear loading and error states, and a manual-ID fallback for private models.
- Added Developer ID signing for the outer DMG as well as the app bundle so
  Gatekeeper can validate both release layers directly.

## 0.2.2

- Fixed Check for Updates from Settings by dismissing the Settings sheet before
  Sparkle presents its updater UI.

## 0.2.1

- Fixed Ask Scribe text visibility and focus on Macs using Dark appearance.
- Suggested questions now populate the input so they can be reviewed or edited
  before asking.
- AI Settings now opens reliably inside Ask Scribe instead of attempting to
  stack a second macOS sheet.
- Added System, Light, and Dark appearance choices with an adaptive warm palette.

## 0.2.0

- Rebuilt Settings rows with consistent icon/text alignment, explicit colors,
  and pointer cursors; replaced the misleading model button with a functional
  model manager.
- Added English, multilingual, and compact local transcription model choices
  with selected, installed, downloading, and failure states.
- Added persistent speaker track names plus per-moment corrections, and made
  transcript timestamps play from the cited moment.
- Added Ask Scribe across one meeting, a project, or the whole library. Local
  cited retrieval is the default; optional Venice, OpenAI, Claude, Grok, and
  OpenAI-compatible connections store API keys in Keychain and redact common
  contact details by default.
- Added project, people, and tag organization; a cross-meeting decision log;
  and editable recap, status, agenda, and task drafts that never send
  automatically.
- Added signed Sparkle updates through GitHub Releases with a Check for Updates
  button in Settings, the app menu, and the menu-bar menu.
- Added 28 automated tests and new native visual-regression screens for model
  and intelligence settings.

## 0.1.0

- Native Scribe meeting library with search, work-and-life sample content,
  editable personal notes, action completion, playback, and Markdown export.
- Explicit Record/Stop controls plus optional call-detection prompts; recording
  never starts automatically.
- Separate microphone and call-app capture for Zoom, Microsoft Teams, Google
  Meet in major browsers, Slack, FaceTime, Webex, and Discord.
- Fully local Parakeet transcription and optional local llama.cpp summaries.
- First-run onboarding, preferences, menu-bar controls, launch at login,
  privacy guidance, app icon, `.app` builder, DMG packaging, and release CI.
- Universal Apple-silicon and Intel Mac installer, signed with Developer ID and
  notarized for normal Gatekeeper installation.
