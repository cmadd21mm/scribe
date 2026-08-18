# Scribe privacy promise

Scribe is designed so a meeting can become useful notes without becoming an
account, an upload, or a data trail.

- Recording starts only after the user chooses **Record**.
- Microphone audio, call audio, transcripts, and notes are stored in a folder
  on the Mac.
- Scribe has no account system, telemetry, analytics, advertising, meeting
  bot, or crash reporter.
- Call detection inspects local Core Audio process activity. It does not read
  messages or join meetings.
- Calendar access is optional and is used only to name a meeting locally.
- Local transcription, summaries, search, and Ask Scribe work without an
  account or network connection.
- Network access occurs only when the user explicitly downloads a model,
  checks for a signed software update, or asks a question after connecting an
  optional AI provider. Provider keys are stored in the Mac Keychain. Remote
  questions send the selected meeting context for that request only; email
  addresses and phone numbers are redacted by default.
- Follow-up drafts are never sent automatically. Scribe only copies text after
  the user chooses to do so.

Because meeting audio can include other people, users are responsible for
following the recording-consent laws and expectations that apply to them.
