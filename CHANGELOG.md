# Changelog

## 0.2.15

- Make an explicit Record action capture system output for every meeting,
  including apps whose audio is routed through an unknown or shared helper.
- Normalize Chromium, Electron, WebKit, and FaceTime helper processes back to
  their parent app for reliable source labels and automatic call prompts.
- Require Safari or FaceTime to be running before attributing Apple's shared
  WebKit or conferencing service, preventing false source labels.
- Detect configured calls when microphone input and speaker output are owned by
  separate processes; output-only browser media still never triggers a prompt.
- Classify an unrecognized recording as online when its system track contains a
  signal, while keeping silent system tracks out of in-person warnings.
- Mark sessions with no usable signal so retained troubleshooting files are not
  repeatedly queued for transcription on every launch.
- Remove long, near-identical overlaps from the microphone transcript when
  speaker playback is already represented by the cleaner system track.
- Clarify in Settings and the README that explicit recording captures system
  output and can therefore include notification or media sounds.

## 0.2.14

- Restored Quill's reliable global system-output capture after a supported call
  is detected and the user explicitly chooses Record. This captures FaceTime's
  `avconferenced` audio and browser/meeting-app helper processes while excluding
  Scribe's own output.
- Added signal-level health checks for both tracks, so valid AAC files filled
  with digital silence can no longer be mistaken for successful recordings.
- Added bidirectional microphone recovery: a silent raw route retries Apple's
  voice-processing route, and a silent voice-processing route retries raw.
- Warn during a recording when an expected track remains silent, explain
  partial capture on stop, and do not enqueue transcription when neither track
  contains a usable signal.

## 0.2.13

- Fixed the AppKit launch boundary so the application run loop no longer
  occupies Swift's MainActor executor. Recording, summary generation, Ask
  Scribe, and their timeout tasks can now execute from UI actions.
- Restored Quill's proven capture-triggered microphone consent path instead of
  relying on a preflight that could report denial without presenting a prompt.
- Start microphone capture before call-audio capture so its consent cannot be
  masked by a separate system-audio permission failure.
- Fixed release-build ownership so Scribe's main controller, window, recording
  actions, and AI actions stay alive for the entire running application.
- Replaced optimizer-dependent lifetime hints with an explicit process-wide
  owner, preventing a visible window from outliving its recording callbacks.
- Made recording controls strongly retain their action controller, added
  phase-specific startup status, and replaced indefinite microphone waits with
  a 20-second recovery error that links to the correct privacy settings.
- Fixed the macOS app lifecycle so clicking Scribe in the Dock or opening it
  again always restores the main window after it has been closed.
- Added standard untitled-file reopen handling so Finder and Launch Services
  activation cannot leave Scribe running invisibly in the background.
- Made command-line start, stop, and quit controls deliver immediately to the
  running app instead of relying on a deferred distributed notification.
- Removed optional Calendar permission from the recording critical path; it is
  now requested only when the user chooses Allow in Settings.
- Added the hardened-runtime Audio Input and Calendar entitlements required for
  macOS to present privacy consent to a Developer-ID-signed Scribe build.
- Corrected release signing so Sparkle is re-signed for library validation while
  privacy entitlements are applied only to the Scribe host app.

## 0.2.12

- Completed an evidence-based light and dark mode design audit across Home,
  onboarding, meetings, summary generation, Ask Scribe, Settings, model setup,
  speaker naming, and renaming.
- Added accessible names and guidance to primary navigation, recording, meeting,
  transcript, AI, and toolbar controls; increased minimum supporting text size.
- Raised the light-mode coral contrast above WCAG AA for small text and added
  consistent pressed feedback to primary and secondary controls.
- Replaced the subtle summary spinner with a clear progress card that names the
  provider, shows elapsed time, explains the timeout, and confirms the current
  note remains safe.
- Added Decisions and Open Questions to meeting details, copied summaries, and
  exported Markdown; long transcripts can now expand and collapse in place.
- Replaced misleading always-success permission icons with current microphone
  and calendar states, while explaining when system-audio access is checked.
- Added unobtrusive confirmations for copy and export actions and strengthened
  the affordance of Ask Scribe suggestions and AI model selection.
- Made Venice Ask Scribe requests use the same responsive, no-web-search mode as
  summaries, with visible elapsed time and a clear 120-second safety limit.
- Moved Keychain reads off the main UI thread and surfaced Keychain approval
  status, so a macOS authorization dialog can never make AI setup or Ask Scribe
  look frozen.

## 0.2.11

- Added a dedicated Home view that opens by default, with a prominent recording
  card, immediate starting/recording feedback, recent meetings, and AI status.
- Fixed main-window recording actions so they return to Home and visibly enter a
  Starting state while Scribe checks microphone and system-audio access.
- Fixed the main-window Meeting AI setup action so it actually opens settings.

## 0.2.10

- Fixed silent recording-start failures: Scribe now brings its window forward
  and explains why recording could not begin.
- Added an Open Settings action for denied microphone and system-audio access,
  taking the user directly to the correct macOS privacy pane.
- Kept failed starts from creating misleading empty meetings while making the
  required recovery action unmissable in the app.

## 0.2.9

- Added visible elapsed time while a meeting summary is being generated, plus
  clear guidance for the normal 10–30 second range and 120-second cutoff.
- Added an inline failure and Try Again state so a transient provider problem
  cannot look like an indefinite spinner.
- Added a private per-meeting `summary.log` containing only provider, duration,
  success, and error metadata—never transcript content or API keys.
- Verified a full 627-line interview with Venice Kimi K3 Fast in 19 seconds and
  preserved the prior note until the validated replacement was complete.

## 0.2.8

- Removed the unconfigured built-in summary state entirely: transcripts remain
  available, while summaries and action items wait for a capable model.
- Added a clear meeting-AI setup prompt anywhere a summary would otherwise
  appear, and disabled summary copying until reliable analysis exists.
- Hid legacy notes marked as generated by the old built-in fallback so they are
  never mistaken for trustworthy meeting analysis.
- Updated Settings and documentation to distinguish local transcription from
  optional local or remote summary models.

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
