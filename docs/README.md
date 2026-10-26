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
| `voice-station-broadcast.html` | B / Broadcast: dark horizontal studio console, microphone bay and mode bank | Retained alternative; A selected 2026-09-08 |
| `voice-station-folio.html` | C / Folio: paper workspace, intention rail and compact capture bar | Retained alternative; A selected 2026-09-08 |
| `voice-station-concept.html` | A / Original station: personal hub with Station, Modes, Your words and Control | Selected 2026-09-08; implemented in `windows/ui/station.html`; live acceptance pending |
| `andor-console-preview.html` | Station window, Andor Telemetry Console redesign | Built and shipped 2026-09-01 |
| `station-redesign-01-signal-chain.html` | Station window, signal-chain redesign | Approved and shipped 2026-09-01; `design-system.md` records the result |
| `station-palette-01-mint-partners.html` | Station window, palette proposals over the mint canvas | Superseded 2026-09-01 by the signal-chain preview; kept for the colour decision it records |
| `hud-design-proposals.html` | Floating HUD, three-row capsule proposals | Built and shipped 2026-09-03; `design-system.md` records the result |
| `menubar-icon-proposals.html` | macOS menu bar icon proposals | Option 7 built and shipped 2026-09-03; `design-system.md` records the result |
| `product-directions.html` | Full-size comparison of three product directions | Proposed 2026-09-08; all interfaces visible on one self-contained page |
| `product-direction-01-focus-home.html` | Focus Home, sidebar and central dictation surface | Selected 2026-09-08; native shell implemented on the evolution branch, not installed for daily use |
| `product-direction-02-compact-deck.html` | Compact Deck, small control window and expandable drawers | Alternative retained for comparison; not selected |
| `product-direction-03-writing-studio.html` | Writing Studio, transcript library and full-text review | Alternative retained for comparison; not selected |
| `history-redesign-01.html` | History, the list inside the unchanged chassis | Approved and built 2026-09-26; `design-system.md` records the result |
| `words-section-01.html` | Words, replacing Modes: corrections, vocabulary and modes | Approved and built 2026-09-27; `design-system.md` records the result |
| `microduck-mascot-01.html` | Floating HUD mascot: three Microduck drawings, five animated states, an articulated rig whose pose follows the voice, colour variants | Rig (§2–3) approved 2026-10-25, one colour; build is `backlog.md` I-82 |
| `hud-redesign-01-microduck.html` | Floating HUD capsule rebuilt around the Microduck: beside, speech bubble and perch layouts, every state | Superseded 2026-10-25 by `hud-redesign-02-bubble.html` |
| `hud-redesign-02-bubble.html` | Floating HUD as a small round-ended capsule beside the duck's head, in three sizes; the duck appears only once a voice is heard | Approved 2026-10-25; `design-system.md` records it; build is `backlog.md` I-82 |

Proposals 02–03 share `product-directions.css`; keep it beside those individual previews.
The [full comparison](product-directions.html) embeds the interfaces, styles and bundled
font, so each design is visible without opening a separate file. It carries its font as a
data URI because its own `Content-Security-Policy` allows no other source; an
in-conversation duplicate of it was deleted on 2026-09-18 rather than kept as a second
copy of the same 157 KB face.
Focus Home is the selected design direction. Sample text, counts and device states
are fictional, and proposed recovery retention is not shipped behavior. Proposal 01
preserves the original concept's layout and uses the bundled pixel font for its chrome.
The previews use the approved palette and bundled font. Focus Home's native dimensions,
type sizes and navigation are recorded in `design-system.md`; the alternatives remain
proposals.

## Selected direction — Focus Home

Selection date: 2026-09-08. Reference:
[01 — Focus Home](product-direction-01-focus-home.html).

The redesign follows the sidebar navigation, central dictation controls and supporting
last-result panel in this concept, retaining the retro palette and brand identity.
Detailed diagnostics belong in a dedicated destination. Compact Deck and Writing Studio
remain comparison references rather than the primary layout.

The current implementation slice is the Focus Home shell over existing capabilities.
Onboarding, complete settings, correction editing and recovery retention remain separate
feature scopes. The selection establishes the visual direction; it does not change the
shipped application or the privacy and behavior requirements in `framework.md`.

Build the isolated native preview with `zsh scripts/build-focus-home-preview.sh` from
the project root. The script prints a new app path under `dist/previews/` and does not
replace the daily-use bundle. Its distinct bundle identifier enters a UI-only delegate:
no capture, personal stores, keychain, clipboard, cloud calls or global hotkey.
The Preview scenarios menu supplies explicitly synthetic history, held-back cleanup
and window-size checks. These samples are not performance evidence.

The preview tests presentation only. Real recording, delivery and permission behavior
remain unverified for the new shell until a separately authorized live acceptance run.

`andor-console-preview.html` carries colours the design system did not have when it was
drawn, and pulls its typefaces from Google Fonts rather than the bundled face. The fonts
never reached the app and are still not approved.

The colours did, in two steps and both times through `design-system.md` first: the status
palette — sage, amber and coral — was approved on 2026-09-01, and the console badge
palette, including the violet, on 2026-09-02. The preview did not authorize them; it
proposed them.

The Broadcast and Folio proposals share `voice-station-alternatives.css` and
`voice-station-alternatives.js`. Their comparison links also open the original
`voice-station-concept.html`, which remains unchanged. The new layouts and relative
surface areas are design proposals, not amendments to `design-system.md`.
