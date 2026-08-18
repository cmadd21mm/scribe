# Scribe 0.2 visual QA

Reference: the user-reported Settings screenshot from August 18, 2026.

## Fixed

- All setting titles now explicitly use Scribe's ink color; no labels disappear
  into the paper background.
- Icons occupy a consistent 28-point column and align with the first line of
  their setting. Text columns no longer shift between rows.
- Controls have distinct visible states and pointer cursors. The transcription
  action now opens a working model manager instead of offering a download for
  an already-installed model.
- Setting cards, dividers, typography, radii, and spacing continue to use the
  existing Scribe design tokens.

## Verified screens

- `docs/images/scribe-settings.png`: Settings at 680 × 760 points.
- `docs/images/scribe-models.png`: installed, selected, and downloadable model
  states at 610 × 490 points.
- `docs/images/scribe-library.png`: main library at 1,440 × 1,024 points with
  Decision Log, Ask Scribe, speaker naming, and timestamp playback controls.

The reference and new Settings renders were reviewed side by side at a common
height. No clipping, color inheritance, baseline, padding, border, or radius
regressions remain in the tested states.
