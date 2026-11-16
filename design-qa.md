# Design QA — History 5B expanded exercise row

- Source visual truth: `/Users/justinyen/coding/motionlog/design/history-storyboard.html`, sections 5B “Row content” and 5C-D “One line”
- Full 5B source screenshot: `/Users/justinyen/coding/motionlog/design-qa-source-5b.png`
- Focused source evidence: 5C-D `#dvD` captured and inspected in the in-app browser at 1280 × 720 pixels
- Implementation screenshot: `/Users/justinyen/coding/motionlog/design-qa-implementation-expanded-row.png`
- Implementation viewport: iOS Simulator portrait, 402 × 874 points at 3× (1206 × 2622 pixels), light mode
- State: authenticated test account, November 2 selected, panel raised to 75%, second exercise expanded with a short result, pain, and note
- Density normalization: the source phone mock is approximately 390 points wide; the native implementation was judged at its 402-point device width, with device chrome excluded from fidelity findings

## Full-view comparison evidence

The 5B reference and implementation preserve the same hierarchy: frozen calendar, raised paper panel, persistent grabber, scrolling day header, summary segments, exercise rows, and floating navigation. The final implementation keeps the day header visible when a row is expanded in the 75% panel state.

## Focused-region comparison evidence

The 5C-D reference and final native state were inspected together at readable size. Both use a downward/upward chevron, one open row, a 20-point heavy result line, blue actual values for a short exercise, black “pain 4” copy, and an italic note with a three-point ink rule. The implementation intentionally uses live MotionLog exercise names and the seeded November 2 result instead of the storyboard’s sample Heel raise copy.

## Required fidelity surfaces

- Typography: native rounded system weights, 20-point result emphasis, italic note treatment, muted prescription text, and numeric styling match the reference hierarchy.
- Spacing: the expanded detail is indented beneath the move name, separated from the prescription by 12 points, and bounded by the existing row divider rhythm.
- Colors: short results use `AppTheme.done`; pain and notes use ink; prescriptions and skipped content use the existing muted tokens.
- Image quality: all visible marks use native SwiftUI/SF Symbols and remain sharp at simulator density; the reference requires no raster imagery.
- Copy: complete rows say “Done”; short rows show the performed result; pain and notes appear only when present; skipped rows say “Not logged this day.” No time is shown.

## Interaction verification

- Expanded a completed row and verified “Done · pain 3.”
- Expanded a short row and verified “2 × 8 · pain 4” plus its note.
- Expanded a skipped row and verified “Not logged this day.”
- Opened another row and verified the previous row collapsed.
- Switched days and verified all exercise rows reset to collapsed.
- Verified half-height rows auto-scroll into view above the floating navigation.
- Verified rows opened in the 75% panel preserve the visible day header.
- Verified VoiceOver exposes each row as a button with Expanded/Collapsed state and a matching hint.

## Findings

No remaining P0, P1, or P2 differences. Expected differences are limited to real exercise names/data, native status-bar chrome, and line wrapping caused by the longer production exercise names.

## Comparison history

1. Initial comparison found a P2 interaction mismatch: automatic row centering also ran in the 75% panel and scrolled the day header away.
2. Limited automatic centering to the half-height panel, where it is needed to clear the floating navigation.
3. Rebuilt, reinstalled, raised the panel first, expanded the short row, and recaptured the final state. The day header remains visible and the focused 5C-D treatment matches.

final result: passed
