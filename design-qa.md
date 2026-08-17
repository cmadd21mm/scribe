# Scribe design QA

**Source visual truth**

`docs/design/scribe-reference.png`

**Rendered implementation**

`docs/images/scribe-library.png`

**Comparison setup**

- State: light-mode meeting library with “Q4 product planning” selected.
- Source: 1487 × 1058 px. Implementation: 1440 × 1024 px.
- Target viewport: 1440 × 1024 points at density 1 for the offscreen SwiftUI
  regression renderer.
- Full-view normalization: each artifact was aspect-fit into a 720 × 512 px
  region and placed side by side in `docs/design/full-comparison.png`.
- Focused normalization: each detail pane was normalized to 1440 × 1024,
  cropped to the same 1040 × 760 region, scaled to 720 × 526, and placed side
  by side in `docs/design/focused-comparison.png`.

## Findings

No actionable P0, P1, or P2 differences remain.

- Fonts and typography: the implementation preserves the editorial serif
  display hierarchy, quiet rounded body text, all-caps wordmark, italic coral
  tagline, and readable small transcript labels. Native macOS system families
  are an intentional open-source distribution choice and keep text accessible.
- Spacing and layout rhythm: the 400-point sidebar now matches the source's
  major-region proportion. The detail column was narrowed to 760 points so the
  summary wraps and sections breathe like the reference. Dividers, margins,
  row grouping, footer placement, and vertical rhythm are aligned.
- Colors and tokens: warm paper, cream sidebar, aubergine ink, coral states,
  subtle tan selection, and low-contrast rules are consistent with the source.
- Image and icon fidelity: the generated app icon follows the same cream,
  aubergine, and coral direction. Visible in-app controls use coherent SF
  Symbols rather than custom or placeholder glyphs.
- Copy and content: “Stay in the conversation.” replaces the requested weak
  tagline. Work-focused sample notes are balanced with realistic life uses.
- States and interactions: library selection, search, Record/Stop, note editing,
  summary copy, action completion, playback, export, settings, onboarding, and
  menu-bar controls are implemented. Disabled demo-only file controls read as
  disabled rather than broken.
- Accessibility and resilience: native controls retain keyboard focus and
  accessibility semantics; title scaling and scrolling prevent clipping at the
  minimum 1040 × 700 window.

## Intentional deviations

- Search, Record, Add note, My Notes, source label, and action checkboxes are
  product-complete additions beyond the static mock, not visual regressions.
- The offscreen evidence excludes macOS window chrome; the shipping window uses
  a native transparent title bar with the standard traffic-light controls.

## Comparison history

1. Initial comparison found a P2 region-proportion mismatch: the implementation
   sidebar was 360 points and the detail content was too wide and dense.
2. The sidebar was increased to 400 points, the detail measure was reduced to
   760 points, and display/body sizing was tuned.
3. Post-fix full-view and focused comparisons show matching major proportions,
   hierarchy, line wrapping, palette, and density. No actionable P0/P1/P2 issue
   remains.

## Follow-up polish

- [P3] A future signed release could bundle a licensed editorial type family if
  the project wants even closer glyph-level matching across macOS versions.

## Implementation checklist

- [x] Match the selected visual language and final tagline.
- [x] Preserve a native Mac window and menu-bar experience.
- [x] Implement the primary library, note, action, transcript, and record flows.
- [x] Verify full-view and focused comparisons after the proportion fix.

final result: passed
