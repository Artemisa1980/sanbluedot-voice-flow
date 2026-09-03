# docs — interface previews

Standalone HTML previews of the application's surfaces, used to see and agree on a
design before it is built in SwiftUI. A preview is a proposal, kept after the fact so a
later redesign starts from what was actually decided rather than from a screenshot.

New previews are written here, one file per surface and revision, named for what they
show.

## The authority a preview does not have

`design-system.md` owns the palette, the type scale and the chrome measurements, and
`../../brand.md` owns the brand above it. A preview illustrates that contract; it never
extends it. Any colour, font or spacing a preview introduces is a proposal that must be
approved into `design-system.md` before it reaches the app — otherwise the shipped
interface drifts toward whichever preview was open last.

Two habits keep a preview honest about what will actually ship:

- Build it from the approved tokens, declared as CSS variables with the same names the
  Swift `VoiceStationTokens` uses, so a mismatch is visible in the file itself.
- Load Press Start 2P from `macos/Resources/Fonts/` rather than from a web font service.
  The app ships the local file; a preview rendering a different cut of the typeface
  predicts the wrong result.

## Previews

Every preview in this directory has a row, superseded ones included. A file with no row
cannot be told apart from one that was missed.

| File | Surface | State |
|---|---|---|
| `andor-console-preview.html` | Station window, Andor Telemetry Console redesign | Built and shipped 2026-09-01 |
| `station-redesign-01-signal-chain.html` | Station window, signal-chain redesign | Approved and shipped 2026-09-01; `design-system.md` records the result |
| `station-palette-01-mint-partners.html` | Station window, palette proposals over the mint canvas | Superseded 2026-09-01 by the signal-chain preview; kept for the colour decision it records |
| `hud-design-proposals.html` | Floating HUD, three-row capsule proposals | Built and shipped 2026-09-03; `design-system.md` records the result |

`andor-console-preview.html` carries colours the design system did not have when it was
drawn, and pulls its typefaces from Google Fonts rather than the bundled face. The fonts
never reached the app and are still not approved.

The colours did, in two steps and both times through `design-system.md` first: the status
palette — sage, amber and coral — was approved on 2026-09-01, and the console badge
palette, including the violet, on 2026-09-02. The preview did not authorize them; it
proposed them.
