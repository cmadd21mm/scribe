# Quill manual test checklist

These checks exercise Core Audio, TCC permissions, EventKit, real call apps,
and `llama.cpp`. Unit tests cannot prove these paths. Run the release binary on
macOS 15+ with headphones first, then repeat one call on speakers with
`mic_voice_processing: true`.

## 1. One-time setup

1. Run `swift test` and `swift build -c release`.
2. Run `sh scripts/check-no-runtime-network.sh`.
3. Install `.build/release/quill` and run `quill models download-transcription`.
4. Run `quill doctor`; resolve any hard failure.
5. Start `quill run` and confirm a feather appears in the menu bar.
6. In another terminal, run `quill apps` while playing audio and confirm it
   prints PIDs, input/output state, and bundle IDs.

For every completed recording below, expect exactly one folder named
`YYYY-MM-DD HHMM - <calendar title or app call>` containing non-empty
`mic.caf`, non-empty `system.caf`, `meta.json`, `transcript.md`,
`transcript.json`, `note.md`, and `transcribe.log`. Expect
`meta.json.schema_version == 1`, `state == "complete"`, and the correct
`source_bundle_id`. Listen to both CAF files: your speech belongs in `mic.caf`;
the remote participant belongs in `system.caf`.

## 2. Consent behavior—no automatic recording

1. Start a configured call and wait longer than `call_prompt_delay_seconds`.
2. Confirm Quill shows **Record** and **Not now** but creates no folder and no
   purple recording indicator before you click.
3. Click **Not now**. Keep the call active for one minute.
4. Confirm Quill does not prompt again and creates no recording.
5. End the call, start a new call, and confirm a new prompt may appear.
6. Play Spotify without any app using microphone input. Confirm no call prompt
   appears; output-only media must not qualify as a call.

## 3. Zoom

1. Join a Zoom call with one remote participant; both people speak.
2. At Quill's prompt, click **Record**.
3. While the call continues, play music in a separate Music or Spotify app and
   trigger a Messages notification.
4. End the Zoom call and wait `call_end_delay_seconds`.
5. Verify the expected folder and files. `system.caf` must contain the remote
   participant, not the separate music or notification sound.

## 4. Microsoft Teams

1. Join a Teams meeting and have both sides speak for at least 30 seconds.
2. Click **Record** in Quill's prompt; share/unshare the screen once to provoke
   possible audio-device reconfiguration.
3. End the meeting and wait for local processing.
4. Verify the expected files, two-sided transcript, structured note, and no
   unrelated output in `system.caf`.

## 5. Google Meet in Chrome

1. Join Meet in Chrome; close or mute unrelated audio tabs for this test.
2. Click **Record**, have both sides speak, then play music in a separate native
   app.
3. End the Meet call and verify the expected files and isolation.
4. Record `meta.json.source_bundle_id`; expect `com.google.Chrome`.

## 6. Google Meet in Safari

1. Join Meet in Safari and click **Record** in Quill's prompt.
2. Have both sides speak, then trigger unrelated audio from a separate app.
3. End the call and verify the expected files and isolation.
4. Expect `meta.json.source_bundle_id` to be `com.apple.Safari` (if Core Audio
   reports a Safari helper bundle instead, add that reported ID from
   `quill apps` to `call_apps` and record it here).

## 7. Slack huddle—native app

1. Start a huddle in the Slack desktop app with a remote participant.
2. Click **Record**, have both sides speak, and receive a notification from a
   different app.
3. End the huddle and verify the expected files and isolation.
4. Expect source bundle ID `com.tinyspeck.slackmacgap`.

## 8. Slack huddle—browser

1. Start a Slack huddle in one configured browser.
2. Click **Record**, have both sides speak, and play unrelated audio in a
   separate native app.
3. End the huddle and verify the expected files and browser source bundle ID.

## 9. FaceTime

1. Place a FaceTime audio or video call and click **Record**.
2. Switch the microphone or output device once during the call.
3. Continue speaking on both sides, end the call, and verify the mic track did
   not stop at the device switch. A repaired gap may be silent but timestamps
   must remain aligned.

## 10. Discord

1. Join a Discord voice channel with a remote participant and click **Record**.
2. Have both sides speak while a different app produces audio.
3. Leave the channel and verify the expected files, isolation, and source
   bundle ID `com.hnc.Discord`.

## 11. Webex

1. Join a Webex meeting and click **Record**.
2. Have both sides speak and exercise mute/unmute once.
3. End the meeting and verify the expected files and isolation.
4. Record whether Core Audio reports `com.cisco.webexmeetingsapp` or
   `Cisco-Systems.Spark`.

## 12. Unknown app—manual selection

1. Start audio input/output in an app not present in `call_apps`.
2. Run `quill apps` and copy its bundle ID.
3. Run `quill start --bundle-id <copied-id> --title "Unknown app test"`.
4. Confirm recording starts only after this command; then run `quill stop`.
5. Verify the expected folder and that unrelated process output is absent.

## 13. Calendar association and denial

1. Create a calendar event covering the current time with title
   `Quill Calendar Test` and two attendees.
2. Record a short call. Expect the folder and `note.md` heading to contain that
   title, and expect both attendees in `meta.json` and `note.md`.
3. Deny Calendars access, record another short call, and confirm recording still
   starts. Expect a notification naming System Settings → Privacy & Security →
   Calendars and an app-and-time fallback title.

## 14. Permission failures

1. Disable microphone access and attempt a recording. Expect no session and a
   message naming System Settings → Privacy & Security → Microphone.
2. Re-enable mic, disable Screen & System Audio Recording, and retry. Expect no
   silent empty system track and a message naming System Settings → Privacy &
   Security → Screen & System Audio Recording.
3. Restore both permissions before continuing.

## 15. Crash recovery

1. Start a recording, speak on both sides for at least 20 seconds, then run
   `kill -9 <quill-pid>` without stopping.
2. Confirm the meeting folder already contains growing CAF files and
   `meta.json` with `state: "recording"`.
3. Relaunch Quill. Expect `state: "interrupted"`, `recovered_at`, a usable
   transcript/note after processing, and no deletion of existing audio.

## 16. Disk reserve

1. Temporarily set `minimum_free_disk_gb` higher than the Mac's available
   space.
2. Attempt to record. Expect a visible free-space error and no audio capture.
3. Restore the normal reserve.

## 17. Structured notes with and without a local model

1. Remove `summarization` from config and process a short meeting. Expect a
   complete `transcript.md` and a `note.md` explicitly saying no local model is
   configured and no network call was made.
2. Configure a real local `llama-cli` and GGUF instruct model, then run
   `quill note <meeting-dir>`.
3. Expect `note.md` to contain Summary, Decisions, Action items, and Open
   questions, plus the local backend/model name. Compare every claim with the
   transcript; fabricated facts fail this test.

## 18. CLI parity

1. Exercise `quill start`, `stop`, `open`, `apps`, `transcribe`, `note`,
   `recover`, `doctor`, and `quit`.
2. Confirm each command acts only on local processes/files and that menu-bar
   start/stop results match CLI start/stop results.
