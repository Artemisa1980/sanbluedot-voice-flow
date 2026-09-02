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

| File | Surface | State |
|---|---|---|
| `andor-console-preview.html` | Station window, Andor Telemetry Console redesign | Built and shipped 2026-09-01 |

`andor-console-preview.html` carries nine colours that are not in `design-system.md`,
including a green, an amber and a red for status states, plus a violet accent. It also
pulls its typefaces from Google Fonts. Neither reached the app, and neither is approved:
a status palette is worth having, but it enters through `design-system.md` first.
