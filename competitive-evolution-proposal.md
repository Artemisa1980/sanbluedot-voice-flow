# VoiceFlow — Personal Voice Station Direction

Status: historical record, not Mac work. Its one durable decision — hub design A,
`docs/voice-station-concept.html` — lives in `design-system.md` since 2026-09-08. The
sequence below belongs to the other platform's own machine (`AGENTS.md`); on this Mac the
open work is `backlog.md`, and `framework.md` remains the behavior authority.

## Product direction

A personal voice workstation with an unobtrusive capture capsule and a deliberate
control hub. The owner controls models, processing destination, vocabulary, corrections,
retention and exports. Ordinary dictation remains local. Rewriting is a visible choice.

The aim is dependable daily dictation with a coherent identity, rather than maximum
feature count. Spanish, English, mixed speech and the owner's terminology form the
acceptance corpus. A competitor's advertised speed is not a performance target measured
on this computer.

## Reference products

The following capabilities are documented by the vendors, not independently tested here.
No proprietary implementation, accuracy ranking or retention guarantee is inferred.

| Reference | Verified published capabilities | Useful direction for VoiceFlow |
|---|---|---|
| [Wispr Flow](https://wisprflow.ai/) | Dictation across applications and automatic text cleanup | A short, interruption-free capture-to-text path |
| [Superwhisper](https://superwhisper.com/) | Offline operation, custom modes, vocabulary, model choices and file transcription | Separate speech recognition from text processing; let the owner configure the intention |
| [VoiceDash](https://voicedash.ai/) | Hotkey dictation, text editing, personal dictionary and snippet libraries | Make reusable words and text blocks easy to find and edit |
| [VoiceInk](https://tryvoiceink.com/docs/introduction) | Local and optional cloud models, context settings, modes, vocabulary, word replacements and selected-text rewriting | Visible configuration and inspectable personal memory |

These sources do not establish which application is best. VoiceInk is not limited to
local-only filler removal: its current documentation explicitly includes optional cloud
providers and rewriting. Unverified internal engines and competitive vulnerability
claims are excluded from this proposal.

## Proposed experience

[Interactive station concept](docs/voice-station-concept.html) illustrates four spaces:

- **Station:** capture, explicit mode, model destination and the last delivery.
- **Modes:** literal, conservative cleanup, translation and structured notes; selected-text
  rewriting follows when the Windows capture and focus contract is reliable.
- **Your words:** inspectable history, vocabulary, confirmed corrections and snippets.
- **Control:** providers, local models, shortcuts, microphone, retention and deliberate export.

The concept uses the approved mint, cream, navy, gold and dot-blue family. A physical
microphone dial gives capture a recognizable focal point; quiet typography and generous
spacing keep the hub readable. Pixel type remains in the product chrome. Layout changes
are proposals until accepted into the design contract. The preview has working navigation,
mode selection and a simulated capsule state; it never captures audio, loads personal
memory, calls a model or changes application settings. No invented telemetry appears.

## Existing foundation and proposed sequence

1. **Stabilize Windows.** Reliable hold/release/cancel, Unicode delivery, verified focus,
   terminal handling, truthful status and recoverable failures. Gate 5 still needs live
   checks in Notepad, VS Code and a browser text field, plus the relevant terminal cases.
2. **Connect the hub.** Reuse the Python engine and Tauri adapter. Expose the existing
   capabilities through working controls, with local history and provider settings made
   explicit. Do not make a visual mockup appear connected before it is.
3. **Compare models.** Establish Base accuracy and latency on one fixed bilingual corpus;
   compare a multilingual Small candidate only after its download is authorized. Keep
   the winner based on measured quality, latency and memory use.
4. **Add deliberate transformations.** Bring mode configuration, snippets and selected-text
   transformation to Windows with raw/final comparison and safe fallback behavior.
5. **Evaluate long recordings separately.** File transcription, meeting audio and
   pronunciation practice have different retention, device and acceptance needs.

Each step retains its applicable acceptance and explicit cold-review authorization.
A preview or passing unit suite does not close a live platform gate.

## Tool decisions

The installed Python + Rust/Tauri + whisper.cpp stack already supports this repair slice.
No additional framework or runtime is needed to start the hub. The machine inventory is
private in `docs/windows-capabilities.local.md` and must stay out of version control.

[whisper.cpp](https://github.com/ggml-org/whisper.cpp) supports Windows CPU inference,
quantization and optional acceleration backends. Quantized or accelerated builds are
candidates to benchmark, not assumed speed improvements. Keep downloads tied to a
concrete experiment, use the upstream release/model links, and verify published hashes
when available. An official source reduces provenance uncertainty; it does not make
software risk-free.

[Tauri's Windows prerequisites](https://v2.tauri.app/start/prerequisites/) define its
build-tool and WebView2 requirements. The local Rust tests compile successfully with the
installed toolchain. Ollama is not on PATH and its service did not answer the diagnostic;
local cleanup needs separate provisioning if it is selected for the next experiment.
No new model, dependency, provider, account or cloud processing was enabled in this slice.

<div align="center">sanblue<sup>dot</sup></div>
