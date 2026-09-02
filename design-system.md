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

- Floor: `760 × 700` of **content**. It is declared once and written to both
  `contentMinSize` and `minSize`, the second converted with
  `frameRect(forContentRect:)`. Each alone fails in its own direction: `minSize` measures
  the window frame including the title bar, so a floor stated only there leaves the
  content roughly 28pt short of what the layout asks for, and the overflow is split top
  and bottom — the header rides up, the footer is clipped. `contentMinSize` alone is not
  enforced once the root view stops declaring a minimum height, and the window can be
  dragged down to a band too short to show a card at all.
- `700pt` is measured, not chosen: at 560 the mode switch and the hold hint fall out of
  the control card, and 687 is the smallest size at which every row is present. Raise it
  again if a row is added to that card.
- The root view declares no minimum height. A layout taller than its container overflows,
  and an overflowing vertical stack loses its first and last children — the header and
  the footer.
- Header `72px` and footer `40px` are fixed. Everything the window gains or loses in
  height is absorbed by the middle section.

## Floating HUD contract

The HUD renders over other applications and must stay legible on any wallpaper, so it is
the one surface that does not use the sage canvas.

- Capsule, radius `18px`, black at 75% opacity over a blurred navy wash, with a
  hairline gradient border from white through dot blue.
- Microphone disc `44px`, navy at 80%, glow tinted by state.
- Twelve VU bars, `9 × 12px`, radius `1.5px`: bars 0–6 dot blue, 7–9 gold, 10–11 the
  on-air red `rgb(255, 69, 59)`. Inactive bars sit at white 10%.
- State badges: `ON AIR` red, processing dot blue, completed green, error red. The
  recording badge names the mode — `ON AIR`, `ON AIR • ES➔EN`, `ON AIR • MEETING`.
- Mode confirmation replaces the twelve bars with four segments, one per mode, at
  `14px` high with `3px` gaps and radius `2px`. The selected segment is filled and the
  rest sit at white 10%, so the confirmation also says what the other modes are. The
  microphone disc carries the mode's glyph while it is shown, and the capsule springs
  between states rather than cutting.
- One accent rule for that strip: every mode lights brand gold `#EFC15E`, except
  `ACTION`, which lights the approved coral `#FF7B6B`. The mode that can act on the
  machine is the only one that reads as live, and no new colour enters the palette.
- Wordmark at `10px` gold with the `dot` at `7px` in `#7CB3E8`.

## Dev-Station Tabbed Console contract

The right card in `VoiceStationWindowView` contains a 3-tab switchable console:

- **Tabs:** `ACTIVITY LOG`, `HISTORY TRAY (X)`, and `SNIPPETS (X)`.
- **Active Tab Pill:** Gold background `#EFC15E` with Navy text `#16213E`, radius `4px`, monospace bold `9px`.
- **Inactive Tab Pill:** Clear background, Gold copy at 70% opacity.
- **Console Screen:** Dark olive ground `consoleBg` `#262319`, gold hairline border at 40% opacity, radius `6px`.
- **Snippet & History Items:** Inset cards with dark overlay at 25% opacity, gold hairline border, monospace `9px`/`10px` typography in `inputCream` `#FFF9E9`.
- **Actions:** Quick buttons styled in semantic tokens (`COPY` in Gold, `RAW` in Dusty Blue, `RE-PASTE` in Dot Blue, `DELETE` in Danger Clay).

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
becomes unconditional.

The macOS keyboard focus ring is suppressed on custom controls. Selection is shown by the
navy fill and the sage lamp; the system ring is a second, foreign selection language
drawn on top of the first.

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
