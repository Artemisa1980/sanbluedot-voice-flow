# VoiceFlow Visual Design Contract

The durable visual reference for this project. Colors and measurements are read from
here, never inferred from a screenshot. The implementation source of truth is
`macos/Sources/VoiceFlowMac/VoiceStationWindowView.swift` (`VoiceStationTokens`) and
`macos/Sources/VoiceFlowMac/RetroMicHUDView.swift`; update this document in the same
work cycle whenever an approved token or chrome measurement changes.

Interface previews live in `docs/`. A preview illustrates this contract and never
extends it: a colour or typeface it introduces is a proposal, approved into this file
before it reaches the app.

`../../brand.md` owns the brand itself and wins on any conflict. This file records how
that brand is applied to a SwiftUI desktop surface. It exists because the station window
previously declared itself compliant with `sanblueᵈᵒᵗ pdf-station/design-system.md`, a
contract belonging to another project, which put this project's appearance under rules
it does not own and cannot see change.

## Selected Windows hub — A / Original station

**This section, down to "The one non-negotiable", governs the Windows hub only.** The macOS
window is Focus Home, below; nothing here changes it.

Approved design direction: `docs/voice-station-concept.html` (A), selected 2026-09-08.
Use its mint canvas, cream panels, navy-and-gold chrome, central microphone dial,
left navigation and four spaces: Station, Modes, Your words and Control.
The preview is the retained composition reference; this contract owns its adoption.
Its controls remain simulated until connected to the engine and verified on Windows.
This selection does not close a functional gate or change the existing macOS layout.
Keep B / Broadcast and C / Folio in `docs/` as alternate references, not implementation targets.

Windows composition update, approved 2026-09-08: retain A's left navigation and illustrated
microphone. Station uses a single-window overview with a four-stage signal chain, engine
strip, capture panel, dark Andor result console and desktop output strip. Header: owner
at left with the actual version in a gold badge, centered retro voice-station title, brand
at right. Footer: centered brand and retro dev-station title on navy with a gold top rule.
The main overview fits the window; long results scroll inside the console. Detailed pages
remain accessible from the left navigation. Provider labels and telemetry reflect the
Windows implementation rather than the sample values in the supplied reference.

Sidebar update, approved 2026-09-09: use the Andor console background `#262319` for the
left navigation. Replace numeric indexes with outlined microphone, sliders, speech bubble
and gear icons beside Station, Modes, Your words and Control. Cream labels and muted blue
icons remain readable on the dark surface; gold indicates the selected page. Keep the
navigation labels and the existing layout.

Provider interaction, approved 2026-09-09: engine selection synchronizes the highlighted
button, cleanup node, local/cloud label, provider setup panel and console footer. Literal
uses the local green cleanup icon; Ollama uses the same local color and Gemini uses gold.
Unconfigured routes display setup-required status, not successful connection indicators.
Their signal cards retain a solid border; the pending lamp and explicit status communicate
readiness. A disabled microphone states that no audio is captured and points to Literal.
LOG uses actual session events, provider tags, timestamps and category counts; RESULT
preserves raw/final recovery. Reference model versions and verified-key claims are not
product state. The original microphone, dark sidebar, fixed header and footer remain.

Detail pages, approved 2026-09-09: insert Snippets immediately after Modes, with an
outlined quotation icon. The navigation order is Station, Modes, Snippets, Your words,
Control. Each detail page has its own terminal frame: navy border and offset shadow,
cream paper `#F8ECCF`, dark text, a compact gold title badge and a fixed bottom status row.
Content scrolls within the frame; the application header and footer stay visible.
Snippets has only its own title, a trigger/optional-description/expansion form and a list
below. Your words retains History, Vocabulary and Corrections, without a Snippets tab.
Modes and Control use the same cream terminal shell around their existing content.
The Station overview retains its dark Andor console and illustrated microphone.

Voice motion, approved 2026-09-09: while recording, native microphone loudness expands
the illustrated microphone disc by at most 4%, with a soft gold ring. The twelve bars
show a short history of measured loudness as different heights, retaining their blue,
gold and coral palette. This is a voice envelope, not a frequency-spectrum measurement.
Silence, capture exit or missing audio updates settle the display. Reduced-motion users
retain the level lights with no disc movement or changing bar heights.

## The one non-negotiable

The `dot` is **always** `#7CB3E8`. `sanblue` adapts: navy `#16213E` on a light surface,
gold `#EFC15E` on a dark one. A lockup drawn in a single color is a defect, because the
contrast between the two words is what identifies the mark.

## Approved palette

Shared with `pdf-station` so the two stations read as one system.

| Role | Token | Value | Use |
|---|---|---:|---|
| Mint-green soft | `appBg` | `#A9D3C0` | Workspace canvas |
| Light amber | `panelBg` | `#F8ECCF` | Cards and masthead text |
| Dusty blue | `panelHeader` | `#98AAB2` | Softened toolbars |
| Deep clay | `controlBg` | `#906961` | Secondary controls, cream text |
| Dark clay | `controlDangerBg` | `#8A615A` | Destructive clay controls |
| Amber/gold | `gold` | `#EFC15E` | Chrome rules, version badge, `sanblue` on dark |
| Navy | `navy` | `#16213E` | Masthead, footer, outlines, primary ink |
| Dot blue | `dotBlue` | `#7CB3E8` | The `dot`, focus and accent identity |
| Accent hover | `accentHover` | `#93C4F0` | Hover state |
| Muted ink | `textMuted` | `#405147` | Secondary text on sage and amber |
| Input cream | `inputCream` | `#FFF9E9` | Inputs and the hold-to-talk surface |
| Clay control text | `controlText` | `#FFF7EF` | Cream on clay |
| Footer muted | `footerMuted` | `#AAB1C1` | Footer copy outside the wordmark |
| Semantic danger | `danger` | `#C0392B` | Errors and the recording indicator |
| Console olive | `consoleBg` | `#262319` | Activity console ground |
| Header button amber | `headerBtnAmber` | `#F4E3BC` | Small header controls |

Clay is a brand surface and never the semantic error color; errors stay red. Dot blue is
an accent for marks and borders, not body text on pale surfaces.

## Status palette — approved 2026-09-01

Four states, taken from the brand's own photo-derived family in
`sanbluedot-portfolio/docs/color-palette.md`, never from the operating system. Before
this existed the interface borrowed `Color.green` from macOS for "ready" and the HUD
invented its own red, so the app's status colour changed with the viewer's system
settings.

| State | Token | Value | Origin |
|---|---|---|---|
| Delivered · lamp on | `ok` | `#5F7050` | Sage-deep, the shade of the sage in the source photograph |
| Working · expanding | `working` | `#D98A2B` | Amber-deep, from the Andor terminal study |
| Recording · error | `rec` | `#FF7B6B` | Coral, already a portfolio accent token |
| Selected · active | `dotBlue` | `#7CB3E8` | Brand canon. This replaces the macOS focus ring |

**Status is never bare ink on the mint canvas.** Measured against `#A9D3C0`: sage-deep
3.26 · amber-deep 1.68 · coral 1.54 · dot 1.35 · gold 1.02, every one under the 4.5 a
small label needs. A state is therefore drawn as a filled pill or lamp carrying a navy
hairline, or it lives inside the dark console, where the same colours reach 4.80 to 8.04.

**The capsule badge is coral in both states.** Sage-deep reads as muddy olive against the
paper card, so READY and ON AIR share one fill and the state is carried by the word and
by the dot, which blinks only while recording. `ok` keeps its role everywhere else — the chain lamps, the console status, the
selected option — where it sits on a dark or a coloured ground and reads clean.

**Ink follows the fill.** A dark fill takes paper ink — sage-deep 5.00 — and a bright
fill takes navy: amber-deep 5.77, coral 6.28, dot 7.17, gold 9.43.

Three of these are brand canon and this file may not redefine them: the dot `#7CB3E8`,
navy `#16213E` and gold `#EFC15E`. `brand.md` owns them, along with the signature gradient
and the typeface map.

## Header contract

- Height `72px`, horizontal padding `20px`, item gap `12px`.
- Navy ground with a `2px` gold rule along the bottom edge.
- No logo. `SANDY.SYSDEV` opens the header at the left edge. The circular badge was
  removed on 2026-09-01: `brand.md` places the colour badge on GitHub, the portfolio and
  social surfaces, never inside an application header, and the mark stays present through
  the wordmark at the header's right and the footer lockup. The badge file remains the
  master for `AppIcon.icns`.
- `SANDY.SYSDEV`: Press Start 2P `12px`, tracking `0.6`, in `panelBg`, at the left edge.
- Version badge: Press Start 2P `8px`, navy on gold, radius `5px`. **Read from
  `CFBundleShortVersionString`**, never typed as a literal — the badge and the bundle
  drifted to `v0.5.0` against `0.2.0` once already.
- Product name: lowercase `retro voice-station`, Press Start 2P `9px`, tracking `0.4`,
  centered **against the header**, not between the side groups. Two equal spacers centre
  it in the leftover space, which pushes it right by half the difference between the two
  groups — 150pt on an 840pt window, measured. It is hidden below a `600pt` header width
  rather than allowed to collide; the window title bar carries the same name.
- The header and the footer never yield height. The middle section is the only elastic
  band, so a short window shortens the workspace and never clips the chrome.
- Wordmark: monospace bold `12px` gold, superscript `dot` at `8px` heavy in `#7CB3E8`
  with `baselineOffset 5`.

## Footer contract

- Height `40px`, navy ground, `2px` gold rule along the top edge.
- Centered monospace bold `10px`.
- Lockup `sanblueᵈᵒᵗ — retro dev-station`: `sanblue` gold, `dot` dot-blue at `7px` with
  `baselineOffset 5`, the remaining copy in `footerMuted`.

## Resizing contract

The window is usable from its floor to full screen, and the chrome is fixed at both ends.

- Floor: `884 × 700` of **content**. It is declared once and written to both
  `contentMinSize` and `minSize`, the second converted with
  `frameRect(forContentRect:)`. Each alone fails in its own direction: `minSize` measures
  the window frame including the title bar, so a floor stated only there leaves the
  content roughly 28pt short of what the layout asks for, and the overflow is split top
  and bottom — the header rides up, the footer is clipped. `contentMinSize` alone is not
  enforced once the root view stops declaring a minimum height, and the window can be
  dragged down to a band too short to show a card at all.
- `884pt` is the sidebar `184`, the workspace padding `44`, the `16` between the cards
  and two `320` floors — the control card's and the console's. At the earlier `760` the
  control card received `196` and spilled over the sidebar.
- `700pt` is measured, not chosen: at 560 the mode switch and the hold hint fall out of
  the control card, and 687 is the smallest size at which every row is present. Raise it
  again if a row is added to that card.
- The root view declares no minimum height. A layout taller than its container overflows,
  and an overflowing vertical stack loses its first and last children — the header and
  the footer.
- Header `72px` and footer `40px` are fixed. Everything the window gains or loses in
  height is absorbed by the middle section.

## Focus Home — selected 2026-09-08, built 2026-09-16

The Focus Home shell replaces the station window's always-visible two-card layout.
Its implementation is `macos/Sources/VoiceFlowMac/FocusHomeView.swift`, composed with the
existing capture, engine, console and snippet controls. The floating HUD is unchanged.

Default content size `1100 × 800`; the `884 × 700` floor and the fixed header and footer
are unchanged, and a reachable saved frame is still respected.

### Sidebar

`184pt` wide, dusty blue, navy ink, `14pt` horizontal and `24pt` vertical padding. Rows
are `43pt` high with `9pt` gaps, gold with navy ink when selected. A `2pt` navy edge
divides it from the canvas.

Destinations, in this order: **Station · Settings · History · Snippets · Words ·
Diagnostics**. Declaration order in `Page` is the displayed order. Counts come from the
live stores. Each row that shows a count also names what it counts to VoiceOver —
"History, 3 dictations" — because the badge is read on its own, where a bare digit
beside a name counts nothing.

Navigation is never locked. A run in flight used to freeze the whole sidebar; it now
refuses exactly one move, leaving Station while the capsule is physically held, because
that button is the control that delivers the release.

The system keyboard focus ring is suppressed on every control in the shell. macOS paints
that ring in the viewer's own accent colour, so the selected row carried a second
selection language in a colour the palette never chose — green on this machine, and
whatever the next person set on theirs.

### The chassis

Five sections are drawn as a screen set into a chassis, `PaperChassis`. It is the chrome
the owner's site uses, without its outer frame: the window is already the frame, and a
frame inside a frame inside a frame spends the height the station needs.

- Title strip: dark olive, `14pt` horizontal and `11pt` vertical padding, `NAME.SYS` in
  the pixel face at `9pt` gold, the subtitle in the same face at 50% gold, and a trailing
  slot for a count or an action.
- The strip continues down both sides at `18pt` and across the foot as a band of the same
  olive. The screen inside has an `8pt` radius and `14pt` of padding.
- The foot carries the console's own status line — state at the left in gold, delivery at
  the right in mint. The band is the console's ground, so nothing is re-tinted to read
  on it.
- Outer: `14pt` radius, `3pt` navy outline, `5pt` solid navy extrusion.

**The title strip replaces the page heading rather than sitting above it.** A section is
named once. The shell has no page headings.

### Two grounds, and what the difference means

`ConsolePalette` carries the six values a console surface is drawn with, so one view
serves both grounds without a second copy of it.

- **Paper** — Settings, History, Snippets and Words. Ground `panelBg`, sunken blocks
  `inputCream`, ink navy, secondary `textMuted`, rules and field outlines the terminal's
  own olive at 45% and 60%. A field on paper is cream on cream, so the outline is what
  draws the box; on the dark ground the fill already did, and the outline is transparent.
- **Terminal** — Diagnostics. The log keeps its dark screen. Its category badges — gold,
  mint, violet, emerald, red — were chosen for a near-black field, and they are what the
  eye scans for a failure.

Paper is what the speaker operates; the dark screen is what the machine emits. The
difference is deliberate rather than left over.

### Station

No title strip and no heading: the signal chain, the engine row, the control card and the
console are all present at once, and the page must not spend height naming itself.

Composition, top to bottom: signal chain · engine row · control card and console split
38/62 with a `320pt` floor and `16pt` gutter · the history reminder in dusty blue at the
foot, `9pt` padding, separated by `20pt`.

The control card holds the state badge, CANCEL while recording, the microphone, the meter
and the mode switch. **System permissions are not here** — they live in Settings, and
here they were the one block that made the card outgrow its own frame. Its scroll view
stays as a floor for a held-back cleanup, which the card carries.

**A held-back cleanup is drawn on Station and in History, and inside the chassis in both
— never on the canvas outside it.** It used to appear above every other page as well. The
result was the same card on six screens, each one outside that section's chassis and
pushing it down to make room. Station carries it in the control card, beside the
microphone and the USE THIS / KEEP MINE buttons that answer it. History carries it inside
the screen above the list, because History is where a delivery is reviewed and the card
is a question about the most recent one.

### The microphone

A ribbon capsule behind a bezel of 36 notches, in a `138pt` box.

It moves like a speaker cone. At rest the swell is ambient and reaches `0.55`; while
recording it is the measured input level, over an ambient floor of `0.12` so that an open
microphone hearing silence reads as powered rather than stopped. Against
`AudioRecorder.currentAudioLevel`, which maps -50 dB to 0, that floor sits near -44 dB —
below ordinary speech, but the margin has not been measured on this machine. The ring expands to
`0.16` of the drive and fades as it goes, the bezel pushes `0.03`, the capsule `0.09`.

R9 applies to motion as much as to figures.

### The meter

Twelve bars with a per-bar phase offset, so one bar rises while its neighbour falls.

How much of the height the wave owns is the state: **65% at rest**, where nothing is being
measured and the movement is decoration, and **22% while recording**, where the height is
a reading of the speaker's voice and a wave large enough to see would be a wave large
enough to lie.

### A delivered transcript in History

A row whose cleanup was replaced by the deterministic transcript carries a coral
`FALLBACK` badge and, beside it, which side refused — the guard rejecting text the
provider did return, or the provider failing to answer. Without it the row was identical
to a successful cleanup: same mode badge, same engine name, and no sign the engine's text
never arrived. The two call for opposite responses, so the record stores the reason
rather than one bit.

**The row, approved 2026-09-26** from `docs/history-redesign-01.html`. Three lines, and
the dictated text is the largest thing in them:

- **Rail** — on the left edge: `ok` delivered, `rec` fallback.
- **Head** — time in brackets, mono bold; mode pill with the HUD's badge name and a
  `FALLBACK` pill, both filled (`dotBlue`, `rec`) with navy ink and a navy hairline;
  engine and delivery in the secondary ink; `TOTAL` as a tracked label beside the
  seconds in Press Start 2P.
- **Reason** — on a fallback only, secondary ink, under the head.
- **Text** — the largest type in the row.
- **Foot** — `▸ ORIGINAL` toggle in the secondary ink; `COPY` gold, `RAW`, `FIX` and
  `RE-PASTE` cream, all with a navy outline. `FIX` appears on every dictation with a raw
  transcript and opens Words with that dictation, to teach a correction. A row fixed by
  the earlier in-row rewrite keeps its gold `FIXED` pill, its fixed text, and BEFORE FIX
  under ORIGINAL. The original opens under the foot as HEARD and
  CORRECTED, and CORRECTED reads "no corrections applied" when the two are the same text.
- **Frame** — the row on `sunkenRow` with a `1pt` rule.

**Two scales, one row.** The History section is where a delivery is read; the station's
console tab sits beside the log at the log's size. `HistoryTypeScale` carries both, so
resizing one never resizes the other. Values in `pt`:

| | Time | Pills | Engine | TOTAL label · figure | Reason | Text · spacing | Controls | Rail | Radius |
|---|---|---|---|---|---|---|---|---|---|
| History section | 10 | 8.5 | 9 | 7.5 · 10 | 9 | 12 · 3.5 | 8.5 | 5 | 9 |
| Station console | 8.5 | 7.5 | 7.5 | 6.5 · 8 | 8 | 9 · 2 | 7.5 | 3 | 6 |

### What each section holds

- **Settings** — `SETTINGS.SYS`. Engine; cloud model and API key when a cloud engine is
  selected; shortcut and permissions. Beside them, at a workspace width of `720pt` or
  more, a `280pt` column stating in plain words what this Mac does with what it hears:
  processing, recording audio, recent dictations. The cloud models are drawn as the
  engines are — same pill, same lamp, same weight — because they are the same kind of
  choice. The key is a card of its own: it is the one control that decides whether text
  leaves the Mac, and it was previously the smallest element on the page.
- **History** — `HISTORY.SYS`. The tray, with CLEAR on the title strip when there is
  something to clear.
- **Snippets** — `SNIPPETS.SYS`. The store editor.
- **Words** — `WORDS.SYS · WHAT IT HEARS, WHAT IT WRITES`, approved 2026-09-27 from
  `docs/words-section-01.html`. It replaced Modes: corrections, vocabulary and modes
  answer one question, which is what happens to what was said. The sidebar count is the
  number of corrections. Three tabs — CORRECTIONS with its count, VOCABULARY with "what
  Whisper listens for", MODES — navy when selected, cream when not. Beside them at
  `820pt` or wider, a `280pt` column: HOW IT WORKS on cream with a `2pt` navy frame, and
  TAKE IT BACK OUT LOUD on navy with the spoken cues as outlined capsules and one worked
  example, the withdrawn words struck through in `rec`.
  - CORRECTIONS: the teach card — IT HEARD → IT SHOULD WRITE, LEARN in gold, the
    one-word checkbox LEARN waits for, and, when FIX opened it, a gold FROM HISTORY tag
    with the dictation's raw text above the fields. Then search, the All / Learned from
    a fix / Added here capsules, and the list: heard struck through in `rec`, written in
    bold, FIX and EVERYWHERE tags, the day, EDIT and DELETE. Newest first.
  - VOCABULARY: add a word; a budget bar in `ok` over `panelBg` saying how many terms fit
    what Whisper reads; each term tagged READ in `dotBlue` or UNREAD in `panelBg`, with
    DELETE and TO CORRECTION.
  - MODES: the mode bank and the four descriptions. Engine selection is not repeated.
  Labels are mono `9pt` tracked in the secondary ink; body mono `11–12pt`.
- **Diagnostics** — `DIAGNOSTICS.SYS`. Telemetry gauges, category filters, the log.

**The five chassis sections do not repeat one another.** Engine selection and permissions
are in Settings, the gauges in Diagnostics, the API key in Settings, the console's tabs
only on Station. Station is the exception by design: it is the station itself, so it
carries the engine row, the mode switch and — when the selected engine is Gemini — the
console's MODEL row, which are also in Settings, in Words and in Settings respectively.

The MODEL row is on the dark console rather than the mint canvas because it explains the
readings directly above it: which model answers, what each one measured, the order the
engine walks when the chosen one is busy, and whether the key is in the keychain. It
appears only when the engine is a cloud one, and disappears with it.

### Refusals

A control a run has locked stays live and answers the press. A gold strip with a navy
edge appears above the page, holds the reason for four seconds and clears itself, and the
same sentence is written to the activity log, where it stays.

This replaces `.disabled`, which refused in silence: the press produced no switch and no
reason, which from the speaker's side is indistinguishable from a broken button. R3c asks
for both halves — the switch refused, and the refusal reported. Three switches use it:
the mode, the engine and the Gemini model.

### What this does not include

A visual correction editor, audio recovery retention, an editable shortcut, and pickers
for the speech and cleanup models. The last three are engine work rather than interface
work and are not in this section's scope.

This section supersedes the earlier main-window composition and mode-selection fill rules
below. Those rules still describe the retained console, engine controls and HUD where
applicable. The separate UI-only preview uses simulated states and never connects capture,
personal stores, keychain, clipboard or providers.

## Floating HUD contract

The HUD renders over other applications and must stay legible on any wallpaper, so it is
the one surface that does not use the sage canvas.

- Panel `330 × 88`, holding three rows beside the microphone disc: status and wordmark,
  meter, telemetry. The content is `44 + 14 + 226` wide inside `14px` horizontal padding,
  which is `312`. **Every one of these numbers is declared once, in `HUDLayout`, and read
  from there by the window, the positioner and the view.** They were literals in three
  files, and the redesign updated the window's creation size while the code that places
  it on screen went on resizing the capsule back to the previous `295 × 74` on every
  show — 17pt narrower than the content, clipped, and silent, because both numbers were
  right when they were written. `VoiceFlowMacCoreChecks` now fails the build if the panel
  is ever smaller than the content it carries.
- Capsule, radius `18px`, black at 85% opacity over a blurred navy wash, with a
  hairline gradient border from white through dot blue.
- Microphone disc `44px`, navy at 85%, glow tinted by state. It draws a vintage ribbon
  microphone — chrome capsule, four horizontal grille ribs, U-cradle and pedestal —
  wherever the state would otherwise carry `mic.fill`, which is every state except two:
  a mode confirmation shows that mode's own glyph, and a cancelled recording shows
  `mic.slash.fill`. The disc's tint changes with the state; the drawing does not.
- Twelve VU bars, `9 × 12px`, radius `1.5px`: bars 0–6 dot blue, 7–9 gold, 10–11 the
  on-air red `rgb(255, 69, 59)`. Inactive bars sit at white 10%.
- `ESC ✕` closes that row at `9px` heavy monospaced in white 50%, while recording and
  only then. The twelve bars and their gaps spend `141pt` of the `226pt` row, so the
  reminder sits in space the bars never used; it is not in the header, where it and the
  wordmark could only ever take turns.
- State badges: `ON AIR` red, processing dot blue, completed green, error red. The
  recording badge names the mode — `ON AIR`, `ON AIR • ES➔EN`, `ON AIR • MEETING`,
  `ON AIR • NOTES` — and, when the frontmost application is a recognized one, the
  target instead of the prefix: `ON AIR • VSCODE`, `NOTES • TERMINAL`.
- **The badge is drawn at fixed size, so a name it cannot fit is not truncated — it
  pushes the wordmark out of the row.** An application short name is therefore capped at
  12 characters. The budget that cap comes from is not quoted here: `VoiceFlowMacCoreChecks`
  computes it from `HUDLayout` and the same font the view uses, and fails the build if the
  widest possible badge overruns the row. A figure copied into prose stops moving with the
  layout; a figure the build recomputes cannot.
- Third row, `14px` high on a black 45% pill with a white 8% hairline: the telemetry
  strip. It states the stage while work is running and the run's own measurements when
  it ends — speaking rate, latency, the model that answered. It never carries a constant
  dressed as a reading; a sample rate nothing measures per run is not shown at all.
- Mode confirmation replaces the twelve bars with one segment per mode, at `14px` high
  with `3px` gaps and radius `2px`. The selected segment is filled and the rest sit at
  white 10%, so the confirmation also says what the other modes are. The strip is built
  from the mode list itself, so a new mode appears without touching this contract — and
  narrows every existing segment when it does. The build checks each mode's label against
  its share of the row rather than trusting a count that was true at five. The microphone
  disc carries the mode's glyph while it is shown, and the capsule springs between states
  rather than cutting.
- One accent rule for that strip: every mode lights brand gold `#EFC15E` except
  `ACTION`, which lights the approved coral `#FF7B6B` (`rec`). It is the one mode that
  acts on the machine instead of writing, so it is the one that reads differently, and
  no new colour enters the palette.
- Wordmark at `10px` gold with the `dot` at `7px` in `#7CB3E8`.

## Menu bar item

The item is the only VoiceFlow surface always on screen, so it carries the run's state
whether or not the HUD or the station window is open.

- At rest it shows Meow-Bubble: a speech bubble with pointy cat ears and three sound
  dots, drawn in code from a `24 × 24` path into an `18 × 18` template image, so macOS
  tints it for the light bar, the dark bar and the pressed state instead of the drawing
  choosing a colour. Selected from `docs/menubar-icon-proposals.html` on 2026-09-03.
- During a run it shows one character instead: `●` recording, `…` processing, `✓`
  delivered, `!` failed. The check returns to the icon after 2.5 seconds, and only if the
  controller is still idle.
- **The image and the title never coexist, and `imagePosition` travels with whichever is
  showing** — `.imageOnly` for the icon, `.noImage` for the character. A button left on
  `.imageOnly` with no image draws nothing at all: measured at zero pixels against 364
  for the same character under `.noImage`. The item went blank in exactly the four states
  that matter, which reads as an application that is not running. One pair of helpers in
  `AppDelegate` owns both writes; nothing else touches the button.
- Left click toggles the station window. Right or Control click opens the menu, whose
  first line is the state and the permission report — including the line that names a
  missing Input Monitoring grant, which is the only place the dead global trigger is
  explained.

## Console badge palette

Nine log categories must be told apart at `7px` on the dark olive console ground, where
the brand family collapses into two readable hues. These tokens are therefore **not brand
colours**, are never used on the mint canvas, and exist only inside the console and the
meter. Approved 2026-09-02, after they had already shipped as literals.

| Token | Value | Use |
|---|---|---|
| `logAction` | `#F39C12` | ACTION badge |
| `logSnippet` | `#A78BFA` | SNIPPET badge |
| `logPaste` | `#2ECC71` | PASTE badge |
| `micHighlight` | `#2C3A63` | the lit half of the microphone's radial gradient |
| `onAir` | `#FF453B` | the meter's last bars and the capsule's ON AIR badge |

The APPLE badge takes `inputCream`, a brand token already readable on the olive ground,
so the third engine needs no new colour. GEMINI is `gold`, and both count under the
AI CLEAN filter. The Mac console has no OLLAMA badge since Ollama left the app.

**Every colour is declared in `VoiceStationTokens` and referenced by name.** A literal
written beside the view that uses it is a copy that stops moving with the token. Four had
already drifted this way — gold, dot blue, and navy in two different files — and `onAir`
was written twice with no token at all, once as hex and once as `1.0/0.27/0.23`. Every
value was correct on the day it was written, which is why nothing ever failed.

A check reads **every** source file in `VoiceFlowMac` and fails the build on a colour
literal outside the token declaration, or on a system colour such as `Color.green` that
follows the viewer's settings instead of this palette. It reads the directory rather than
a list: an earlier version named three files and reported the interface clean while
eleven went unread.

## Console filters

Six chips filter the activity log by category, with the count in parentheses and the
count hidden at zero. A seventh, `ERRORS`, appears only while it holds something: its
arrival is the signal, and the row has no width for a chip that would read zero almost
always. Warnings and failures live there rather than inside `SYSTEM`, where one failure
sat among thirty routine lines and was not found.

## Engine information mark

Each engine option carries a `?` **inside** its own slab, in the space the short name
already leaves empty on the right. It costs the row no width, and it belongs visually to
the engine it explains.

- `15 × 15px`, radius `4px`, flat. A slab inside a slab reads as noise at this size, so
  the mark takes no border and no extrusion — depth stops at the Control tier.
- It carries the **opposite fill of the slab it sits in**: navy with paper text on an
  unselected option, gold with navy text on the selected one. One rule, legible in both.
- It sits against the slab's right border, not beside the name. The three marks then
  line up down the row, which is what makes the bank read as one control. Placing each
  mark next to its own name was tried and rejected: the column went ragged.
- It is a sibling of the selection button, never nested inside it, and both carry
  `contentShape(Rectangle())`. Pressing a question must not change where the speaker's
  words are about to go, and the empty half of the slab must still select the engine.
- The selection button keeps its own trailing spacer, so it fills the slab and the mark
  is pushed to the border by it. Moving that spacer out to push the mark instead shrank
  the button to the width of its text and left most of the slab dead to the click.

It opens a popover on the dark olive console ground, `290px` wide, listing measured facts
as label and value pairs with the gold label at `7px` and the value in cream at `9px`,
then one line of recommendation, then the date the figures were taken.

The panel states only what was measured. An engine with no measurement says so rather
than offering an estimate: a figure invented inside a panel built to help someone decide
makes the decision for them.

## Dev-Station Tabbed Console contract

The right card in `VoiceStationWindowView` contains a 3-tab switchable console:

- **Tabs:** `TELEMETRY LOG`, `HISTORY TRAY`, and `SNIPPETS`. The owner chose
  `TELEMETRY LOG` over `ACTIVITY LOG` on 2026-09-18. The tabs carry no counts: the
  sidebar rows already do, and a number in both places is the same fact named twice.
- **Active Tab Pill:** Gold background `#EFC15E` with Navy text `#16213E`, radius `4px`, monospace bold `9px`.
- **Inactive Tab Pill:** Clear background, Gold copy at 70% opacity.
- **Console Screen:** Dark olive ground `consoleBg` `#262319`, gold hairline border at 40% opacity, radius `6px`.
- **Snippet Items:** Inset cards with dark overlay at 25% opacity, gold hairline border, monospace `9px`/`10px` typography in `inputCream` `#FFF9E9`.
- **History Items:** the History row above, drawn on this ground's own tokens.
- **Actions:** Quick buttons styled in semantic tokens (`DELETE` in Danger Clay on snippets); History's buttons follow the History row.

## Typography

| Stack | Face | Use |
|---|---|---|
| pixel | Press Start 2P | `SANDY.SYSDEV`, version badge, `retro voice-station` |
| mono | System monospaced | Wordmark, buttons, labels, console |

Press Start 2P is bundled at `macos/Resources/Fonts/PressStart2P-Regular.ttf`, declared
through `ATSApplicationFontsPath`, and registered at view-model init through
`CTFontManagerRegisterFontsForURL`. The application must never request a font from the
network.

**Per-surface by design, not drift.** `brand.md` records that Press Start 2P is the one
constant across the brand and that every other face is the surface's own choice: the web
pulls VT323 and Space Grotesk from Google Fonts, `pdf-station` bundles Fira Code, and this
project uses the system monospaced face rather than paying to bundle a second family. The
two stations therefore do not render identical wordmarks, and that is accepted.

## Shape and interaction — three tiers of depth

Depth carries importance. Everything drawn at one weight is the flatness this window had
before 2026-09-01, when a container, its panels and its buttons all shared one radius and
one shadow, and the eye had no entry point.

| Tier | What it is | Border | Radius | Extrusion |
|---|---|---|---:|---|
| Container | the two cards, the window | `3px` navy | `14px` | `5pt` |
| Panel | chain stage, engine bank, delivery strip | `2px` navy | `10px` | `3pt` |
| Control | engine option, mode tile | `1.5–2px` navy | `7–9px` | `2pt`, `3pt` when selected |

### The extrusion is a slab, never a shadow

The side of a control is a filled shape of the same radius, drawn behind the face and
offset down and right. It is **not** `shadow(radius: 0)`: that projects a copy of the
whole view, border included, and the copy's own outline appears above and to the left, so
the control reads as two buttons stacked. Use the `retroExtrusion` modifier.

The slab is **solid navy at full opacity**. At 85% it reads as dirt under the control
instead of the side of the same piece.

A **selected** control extrudes in clay-deep `#7A544B` rather than navy. Warm against
cool is what makes the active choice read as pressed rather than merely dark.

### The frame carries state

Every chain stage is drawn solid: all four are part of the path a dictation travels, and
a stage that fades out reads as missing rather than as idle. Literal cleanup is a
configuration, not an absence — the text still passes through that stage, and the label
already says `no cleanup`.

**The lamp carries the evidence.** It turns sage only once that stage has actually run:
input from a recording or a recovered transcript, speech from a measured recognition,
cleanup from a measured cleanup, output from a delivered dictation. Hardcoding a stage
lit was the defect the 2026-09-01 gate found; fading an unused stage out was the
overcorrection that followed. The frame says the stage exists, the lamp says it ran.

### Focus

The macOS keyboard focus ring is suppressed on custom controls, through
`focusEffectDisabled`, which is macOS 14. The package's floor is macOS 13, where the call
is a no-op and the system ring still draws; that is accepted rather than worked around,
because the development Mac runs well past that floor. Raise the package floor and this
becomes unconditional. Selection is shown by the navy fill and the sage lamp; the system
ring is a second, foreign selection language drawn on top of the first.

## Logo assets

Two files, one purpose each. Both are 1024 × 1024 with a real alpha channel.

| File | Shape | Use |
|---|---|---|
| `assets/voiceflow-badge-round.png` | Circular, transparent outside the disc | Badge master; copied to `macos/Resources/`. No longer rendered in the header since 2026-09-01 |
| `assets/voiceflow-app-icon.png` | Full-bleed square | Master for `AppIcon.icns`, where macOS applies its own squircle |

`assets/retro-mic-ui-mockup.jpg` is a HUD mockup, not a logo.

### Corrected 2026-08-31, verified by pixel count

| Was | Now |
|---|---|
| The round badge was a white square with a disc painted on it — 99.4% of its outer frame was opaque white | Real circular alpha: 0 white border pixels, all four corners fully transparent |
| `sanblue` was mid-blue `#64A7DC` on a light field | Navy `#16213E`, 13,734 exact pixels in the square and 11,338 in the round |
| The `dot` carried the same blue as `sanblue`, leaving the lockup with no internal contrast | `#7CB3E8`, ~1,045 exact pixels in each |
| `voiceflow-app-icon.png` and `voiceflow-app-icon-square.png` were byte-identical, and two JPG copies duplicated both | The three redundant files are deleted |

The repaint recovers each pixel's ink coverage against the local field and re-composites
the new colour at that same coverage, so glyph antialiasing survives. Coverage is scaled
against the modal ink red measured per region per file: the two masters shipped different
ink values (`#64A7DC` and `#72ACDC`), and one hardcoded value leaves the other at a
washed-out `#344458`.

### Resolved against the brand canon, 2026-08-31

| Question | Answer |
|---|---|
| Is the mint field off-canon? | No. It measures `#AACFBE` on the round file and `#A9CEBB` on the square, both within 10 of `--mintsoft #A9D3C0` in `sanbluedot-portfolio/docs/color-palette.md`. It is that colour with render variance, not an invented one. |
| Is the rainbow hexagon off-canon? | No, and the opposite. It is the brand's signature gradient, now recorded in `brand.md`: `linear-gradient(120deg, #FF6EA9, #A78BFA, #7CB3E8, #EAB13F)`, the same ramp used on the portfolio title and the career-timeline rail. Never flatten it. |

### Note

A separate navy badge exists at `projects-website/sanbluedot-portfolio/dist/sanblue-badge.png`,
but only at 557 px. No navy master was found above that size, so adopting that design here
would mean upscaling these 1024² files.
