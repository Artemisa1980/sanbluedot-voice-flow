import argparse
import json
import sys
from pathlib import Path
from typing import Sequence

from .cleaners import CLEANER_NAMES, DEFAULT_GEMINI_MODEL, build_cleaner
from .clipboard import copy_text
from .credentials import (
    KEYCHAIN_SERVICE,
    delete_api_key,
    describe,
    environment_variable,
    store_api_key_interactively,
)
from .distill import (
    DEFAULT_BASE_MODEL,
    DEFAULT_DISTILLED_MODEL_NAME,
    DistillationPair,
    DistillationStore,
    build_modelfile,
    create_ollama_model,
    write_modelfile,
)
from .doctor import run_checks
from .errors import CleanupFailed, VoiceFlowError
from .memory import (
    DEFAULT_VOCABULARY,
    CorrectionStore,
    build_initial_prompt,
    correction_needs_global_confirmation,
    export_memory,
    load_vocabulary,
)
from .practice import (
    PracticeStore,
    compare,
    record,
    recovered_words,
)
from .pipeline import DictationPipeline
from .snippets import Snippet, SnippetStore
from .transcribers import WhisperCppTranscriber


DEFAULT_WHISPER_MODEL = Path("models/ggml-large-v3-turbo.bin")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="voiceflow")
    subparsers = parser.add_subparsers(dest="command", required=True)

    provider = subparsers.add_parser(
        "provider",
        help="Inspect or change the stored cloud provider key.",
    )
    provider.add_argument(
        "action",
        choices=["status", "set-key", "forget"],
        help="status reveals nothing; set-key prompts; forget removes the stored key.",
    )
    provider.add_argument(
        "name",
        nargs="?",
        default="gemini",
        help="Provider name; defaults to gemini.",
    )

    doctor = subparsers.add_parser("doctor", help="Inspect local engine dependencies.")
    doctor.add_argument("--whisper-bin", default="whisper-cli")
    doctor.add_argument("--whisper-model", type=Path)
    doctor.add_argument("--ollama-url", default="http://127.0.0.1:11434")
    doctor.add_argument("--ollama-model", default="qwen3:4b")

    process = subparsers.add_parser("process", help="Transcribe one local audio file.")
    process.add_argument("audio", type=Path)
    process.add_argument("--whisper-bin", default="whisper-cli")
    process.add_argument("--whisper-model", type=Path, required=True)
    process.add_argument("--language", default="auto", choices=["auto", "en", "es"])
    process.add_argument("--cleaner", choices=list(CLEANER_NAMES), default="literal")
    process.add_argument(
        "--mode",
        choices=["clean", "translate", "meeting", "transform"],
        default="clean",
        help="Processing mode: clean, translate (ES -> EN), meeting (notes & action items), or transform (selection).",
    )
    process.add_argument(
        "--context-text",
        default=None,
        help=(
            "Reference text or highlighted selection to transform. Typed deliberately "
            "at a terminal; the application uses --context-text-stdin instead."
        ),
    )
    process.add_argument(
        "--context-text-stdin",
        action="store_true",
        help=(
            "Read the selection to transform from standard input. A caller that holds "
            "the speaker's screen content uses this: an argument is visible to every "
            "process the user runs, and `ps -ww -ax` prints it in full."
        ),
    )
    process.add_argument(
        "--app-name",
        default=None,
        help="Frontmost application name, substituted for the {app} snippet macro.",
    )
    process.add_argument("--ollama-url", default="http://127.0.0.1:11434")
    process.add_argument("--ollama-model", default="qwen3:4b")
    process.add_argument("--gemini-model", default=DEFAULT_GEMINI_MODEL)
    process.add_argument("--copy", action="store_true")
    process.add_argument(
        "--json",
        action="store_true",
        help="Emit raw, personalized, and final transcript data as one JSON object.",
    )
    process.add_argument(
        "--no-memory",
        action="store_true",
        help="Ignore the local vocabulary and confirmed corrections for this run.",
    )
    process.add_argument(
        "--no-vocab-prompt",
        action="store_true",
        help=(
            "Stop biasing the speech engine with the confirmed vocabulary. The prompt "
            "is enabled by default because it improved the fixed local replay corpus."
        ),
    )
    process.add_argument(
        "--distill",
        action="store_true",
        help=(
            "Keep this dictation as a local distillation pair. Off by default: it "
            "stores the spoken text on disk, so it is a deliberate choice, never a "
            "side effect of using cloud cleanup. Delete the store with "
            "`vf distill clear --yes`."
        ),
    )

    subparsers.add_parser("memory", help="Inspect the local vocabulary and corrections.")

    correct = subparsers.add_parser("correct", help="Confirm one correction pair.")
    correct.add_argument("--heard", required=True, help="What the engine wrote.")
    correct.add_argument("--intended", required=True, help="What you actually said.")
    correct.add_argument(
        "--allow-global",
        action="store_true",
        help="Confirm that a single-word trigger may rewrite that word everywhere.",
    )

    forget = subparsers.add_parser("forget", help="Delete one confirmed correction.")
    forget.add_argument("--heard", required=True)

    export = subparsers.add_parser(
        "export", help="Write vocabulary, corrections and practice history to one file."
    )
    export.add_argument("--to", type=Path, required=True, help="Destination JSON file.")

    practice = subparsers.add_parser(
        "practice",
        help="Read a known text aloud and see which words the engine did not recover.",
    )
    practice.add_argument("--text", help="The reference text to read.")
    practice.add_argument("--text-file", type=Path, help="Read the reference from a file.")
    practice.add_argument("--whisper-model", type=Path, help="Override the speech model.")
    practice.add_argument("--whisper-bin", default="whisper-cli")
    practice.add_argument("--language", default="auto", choices=["auto", "en", "es"])
    practice.add_argument("--list", action="store_true", help="List kept sessions.")
    practice.add_argument("--delete", type=int, metavar="ID", help="Delete one session.")

    distill = subparsers.add_parser(
        "distill",
        help="Manage local knowledge distillation dataset and Ollama Modelfiles.",
    )
    distill_sub = distill.add_subparsers(dest="distill_action", required=True)

    distill_list = distill_sub.add_parser("list", help="List distillation pair counts and examples.")
    distill_list.add_argument("--mode", choices=["clean", "translate", "meeting", "all"], default="all")

    distill_record = distill_sub.add_parser("record", help="Record one raw -> cleaned pair manually.")
    distill_record.add_argument("--raw", required=True, help="Raw speech transcript.")
    distill_record.add_argument("--cleaned", required=True, help="High-quality cleaned/translated text.")
    distill_record.add_argument("--mode", choices=["clean", "translate", "meeting"], default="clean")
    distill_record.add_argument("--cleaner", default="gemini")
    distill_record.add_argument("--model")

    distill_modelfile = distill_sub.add_parser("modelfile", help="Generate an Ollama Modelfile.")
    distill_modelfile.add_argument("--base-model", default=DEFAULT_BASE_MODEL)
    distill_modelfile.add_argument("--mode", choices=["clean", "translate", "meeting", "all"], default="all")
    distill_modelfile.add_argument("--out", type=Path, help="Save to file instead of printing.")

    distill_create = distill_sub.add_parser("create", help="Create the distilled model in local Ollama daemon.")
    distill_create.add_argument("--name", default=DEFAULT_DISTILLED_MODEL_NAME)
    distill_create.add_argument("--base-model", default=DEFAULT_BASE_MODEL)
    distill_create.add_argument("--mode", choices=["clean", "translate", "meeting", "all"], default="all")
    distill_create.add_argument("--ollama-url", default="http://127.0.0.1:11434")

    distill_export = distill_sub.add_parser("export", help="Export distillation pairs to JSONL.")
    distill_export.add_argument("--to", type=Path, required=True)
    distill_export.add_argument("--mode", choices=["clean", "translate", "meeting"])

    distill_clear = distill_sub.add_parser(
        "clear",
        help="Delete every stored distillation pair and the store file itself.",
    )
    distill_clear.add_argument(
        "--yes",
        action="store_true",
        help="Confirm the deletion. The pairs contain dictated text and are not recoverable.",
    )

    snippet = subparsers.add_parser(
        "snippet",
        help="Manage voice snippets and spoken macro text expansions.",
    )
    snippet_sub = snippet.add_subparsers(dest="snippet_action", required=True)

    snippet_list = snippet_sub.add_parser("list", help="List registered voice snippets.")

    snippet_add = snippet_sub.add_parser("add", help="Add or update a voice snippet.")
    snippet_add.add_argument("--trigger", required=True, help="Spoken trigger phrase (e.g. 'mi linkedin').")
    snippet_add.add_argument("--expansion", required=True, help="Replacement text or template.")
    snippet_add.add_argument("--description", help="Optional description.")

    snippet_delete = snippet_sub.add_parser("delete", help="Delete a voice snippet.")
    snippet_delete.add_argument("--trigger", required=True, help="Trigger phrase to remove.")

    snippet_export = snippet_sub.add_parser("export", help="Export snippets to JSON.")
    snippet_export.add_argument("--to", type=Path, required=True)

    snippet_import = snippet_sub.add_parser("import", help="Import snippets from JSON.")
    snippet_import.add_argument("--from", dest="from_path", type=Path, required=True)
    return parser


def _provider(args: argparse.Namespace) -> int:
    """Report or change one provider credential without ever printing it."""
    name = args.name
    try:
        if args.action == "status":
            print(f"{name}: {describe(name)}")
            print(f"  keychain service  {KEYCHAIN_SERVICE}, account {name}")
            print(f"  environment       {environment_variable(name)}")
            return 0
        if args.action == "set-key":
            print(
                f"Paste the {name} API key at the prompt. It is stored in the macOS "
                "keychain and never written to a project file."
            )
            store_api_key_interactively(name)
            print(f"{name}: {describe(name)}")
            return 0
        removed = delete_api_key(name)
        print(f"{name}: {'key removed' if removed else 'no key was stored'}")
        return 0 if removed else 1
    except VoiceFlowError as exc:
        print(str(exc), file=sys.stderr)
        return 1


def _doctor(args: argparse.Namespace) -> int:
    checks = run_checks(
        whisper_binary=args.whisper_bin,
        whisper_model=args.whisper_model,
        ollama_url=args.ollama_url,
        ollama_model=args.ollama_model,
    )
    for check in checks:
        marker = "PASS" if check.ok else "MISSING"
        print(f"[{marker}] {check.name}: {check.detail}")
    return 0 if all(check.ok for check in checks) else 1


def _memory(args: argparse.Namespace) -> int:
    del args
    terms = load_vocabulary()
    prompt = build_initial_prompt(terms)
    in_prompt = len(prompt.split(", ")) if prompt else 0
    print(f"Vocabulary: {len(terms)} terms, {in_prompt} fit the engine prompt.")
    print(f"  file: {DEFAULT_VOCABULARY}")

    store = CorrectionStore()
    corrections = store.load()
    print(f"Corrections: {len(corrections)} confirmed.")
    print(f"  file: {store.path}")
    for item in corrections:
        print(f"  {item.heard!r} -> {item.intended!r}  ({item.confirmed_at})")
    return 0


def _correct(args: argparse.Namespace) -> int:
    if (
        correction_needs_global_confirmation(args.heard)
        and not getattr(args, "allow_global", False)
    ):
        print(
            "A single-word correction rewrites that word everywhere. Review the pair, "
            "then repeat with --allow-global if that global behavior is intended.",
            file=sys.stderr,
        )
        return 1
    try:
        confirmed = CorrectionStore().add(args.heard, args.intended)
    except (ValueError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(f"Confirmed: {confirmed.heard!r} -> {confirmed.intended!r}")
    return 0


def _forget(args: argparse.Namespace) -> int:
    if not CorrectionStore().remove(args.heard):
        print(f"No confirmed correction for {args.heard!r}.", file=sys.stderr)
        return 1
    print(f"Deleted: {args.heard!r}")
    return 0


def _export(args: argparse.Namespace) -> int:
    try:
        written, counts = export_memory(args.to)
    except OSError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(f"Exported to {written}. Audio is not included; copy it separately.")
    # Name what left the machine. Distillation pairs are the speaker's own sentences,
    # and an export that carries them without saying so is not a choice they made.
    for section, count in counts.items():
        print(f"  {section.replace('_', ' ')}: {count}")
    return 0


def _practice(args: argparse.Namespace) -> int:
    store = PracticeStore()

    if args.delete is not None:
        try:
            removed = store.remove(args.delete)
        except (OSError, ValueError) as exc:
            print(f"The practice session could not be deleted: {exc}", file=sys.stderr)
            return 1
        if not removed:
            print(f"No practice session {args.delete}.", file=sys.stderr)
            return 1
        print(f"Deleted session {args.delete} and its recording.")
        return 0

    if args.list:
        sessions = store.load()
        print(f"{len(sessions)} kept session(s) in {store.directory}")
        for item in sessions:
            missed = item.get("missed") or []
            print(f"  {item['id']:>3}  {item['recorded_at']}  {len(missed)} missed  "
                  f"{item['audio_file']}")
        return 0

    reference = args.text
    if args.text_file:
        try:
            reference = args.text_file.read_text(encoding="utf-8").strip()
        except (OSError, UnicodeDecodeError) as exc:
            print(f"The practice text could not be read: {exc}", file=sys.stderr)
            return 1
    if not reference:
        print("Give the text to read with --text or --text-file.", file=sys.stderr)
        return 1

    # Remove any take a previous run reserved and never indexed, before reserving one
    # more. Those are recordings of the speaker that nothing can list or delete. The
    # store does the reading and the sweeping under one lock, and leaves alone anything
    # young enough to still be recording: sweeping those destroyed a live take.
    stranded = store.sweep_orphans()
    for path in stranded:
        print(f"Removed a stranded recording from an interrupted run: {path.name}")

    print(f"\nRead this aloud:\n\n  {reference}\n")
    audio = store.next_audio_path()
    try:
        record(audio)
        transcriber = WhisperCppTranscriber(
            model_path=args.whisper_model or DEFAULT_WHISPER_MODEL,
            binary=args.whisper_bin,
            language=args.language,
            # No vocabulary prompt here. Practice measures how the speech lands on its
            # own; biasing the engine toward known terms would flatter the result.
        )
        heard = transcriber.transcribe(audio).text
    except VoiceFlowError as exc:
        # Nothing indexes this take, so leaving it would strand a recording of the
        # speaker's voice on disk with no way to list or delete it.
        audio.unlink(missing_ok=True)
        print(str(exc), file=sys.stderr)
        return 1

    if recovered_words(reference, heard) == 0:
        audio.unlink(missing_ok=True)
        print(f"Heard: {heard}\n", file=sys.stderr)
        print(
            "Nothing from the text came through, so this is a failed take rather than "
            "a pronunciation result. Check the microphone and read a little louder.",
            file=sys.stderr,
        )
        return 1

    try:
        session = store.add(reference, heard, audio)
    except (OSError, ValueError) as exc:
        audio.unlink(missing_ok=True)
        print(f"The practice session could not be saved: {exc}", file=sys.stderr)
        return 1
    differences = compare(reference, heard)
    missed = [item for item in differences if item.kind == "missed"]
    formatting = [item for item in differences if item.kind == "formatting"]

    print(f"Heard: {heard}\n")
    if not missed:
        print("Every word came through.")
    else:
        print(f"{len(missed)} word(s) did not come through:")
        for item in missed:
            print(f"  {item.read or '(nothing)'}  ->  {item.heard or '(dropped)'}")
    if formatting:
        print(f"\n{len(formatting)} formatting difference(s), not pronunciation:")
        for item in formatting:
            print(f"  {item.read}  ->  {item.heard}")

    print(f"\nSession {session['id']}. Listen with:  open '{audio}'")
    return 0


def _timings(
    transcribe_seconds: float | None,
    cleanup_seconds: float | None,
) -> dict[str, float | None]:
    """The stage durations this run actually measured.

    A stage that did not run reports `null`. The field exists so an interface can show
    a latency it was given instead of one it invented, and a missing measurement must
    reach that interface as missing.
    """
    return {
        "transcribe_seconds": (
            None if transcribe_seconds is None else round(transcribe_seconds, 3)
        ),
        "cleanup_seconds": (
            None if cleanup_seconds is None else round(cleanup_seconds, 3)
        ),
    }


def _process(args: argparse.Namespace) -> int:
    mode = getattr(args, "mode", "clean")
    # Transform asks a model to rewrite the selection. The literal cleaner has no model,
    # so the pair produced a plain dictation while the interface said TRANSFORM: the
    # selection was read, sent nowhere and silently dropped. Refused where the two are
    # first seen together rather than left to fail quietly downstream.
    if mode == "transform" and args.cleaner == "literal":
        print(
            "Transform needs a cleaner that can rewrite text. Choose gemini or ollama, "
            "or switch the mode back to clean.",
            file=sys.stderr,
        )
        return 1

    context_text = getattr(args, "context_text", None)
    if getattr(args, "context_text_stdin", False):
        # The selection arrives from another application's text storage, so it can be
        # anything, including bytes that are not valid UTF-8. A traceback here would
        # discard a recording the speaker already made; the run is refused in the same
        # controlled shape as every other failure in this command.
        try:
            stdin_text = sys.stdin.read().strip()
        except (OSError, UnicodeDecodeError) as exc:
            print(
                f"The highlighted selection could not be read: {exc}",
                file=sys.stderr,
            )
            return 1
        context_text = stdin_text or None

    corrections = () if args.no_memory else tuple(CorrectionStore().load())
    snippets = () if args.no_memory else tuple(SnippetStore().load())
    use_prompt = not args.no_vocab_prompt and not args.no_memory
    initial_prompt = build_initial_prompt(load_vocabulary()) if use_prompt else ""

    transcriber = WhisperCppTranscriber(
        model_path=args.whisper_model,
        binary=args.whisper_bin,
        language=args.language,
        initial_prompt=initial_prompt,
    )
    cleaner = build_cleaner(
        args.cleaner,
        mode=mode,
        ollama_model=args.ollama_model,
        ollama_url=args.ollama_url,
        gemini_model=args.gemini_model,
    )
    pipeline = DictationPipeline(
        transcriber=transcriber,
        cleaner=cleaner,
        corrections=corrections,
        snippets=snippets,
        context_text=context_text,
        app_name=getattr(args, "app_name", None),
    )

    try:
        result = pipeline.process(args.audio)
    except CleanupFailed as exc:
        print(str(exc), file=sys.stderr)
        # Emit before copying: a clipboard failure must never discard the words the
        # speaker already produced.
        if getattr(args, "json", False):
            print(
                json.dumps(
                    {
                        "raw_text": exc.raw_text,
                        "personalized_text": exc.fallback_text,
                        "final_text": exc.fallback_text,
                        "language": exc.language,
                        "cleaner": args.cleaner,
                        "used_fallback": True,
                        "fallback_reason": exc.reason,
                        "rejected_text": exc.rejected_text,
                        "timings": _timings(
                            exc.transcribe_seconds, exc.cleanup_seconds
                        ),
                    },
                    ensure_ascii=False,
                )
            )
        else:
            print(exc.fallback_text)
        if args.copy:
            try:
                copy_text(exc.fallback_text)
            except VoiceFlowError as output_error:
                print(str(output_error), file=sys.stderr)
                return 1
        return 2
    except VoiceFlowError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    # Keeping the spoken text on disk is a privacy decision, so it happens only when
    # this run was explicitly asked for it. Cloud cleanup alone is not consent: the
    # speaker chose a provider for one dictation, not a permanent archive of every
    # sentence. A failure to write is reported rather than swallowed, because a store
    # the speaker believes is filling and is not would make the dataset a lie.
    if getattr(args, "distill", False) and result.cleaner == "gemini":
        try:
            DistillationStore().record(
                raw_text=result.raw_text,
                cleaned_text=result.final_text,
                mode=getattr(args, "mode", "clean"),
                cleaner=result.cleaner,
                model=getattr(cleaner, "answered_with", None),
            )
        except (VoiceFlowError, OSError) as exc:
            print(f"The distillation pair was not recorded: {exc}", file=sys.stderr)

    if getattr(args, "json", False):
        print(
            json.dumps(
                {
                    "raw_text": result.raw_text,
                    "personalized_text": result.personalized_text,
                    "final_text": result.final_text,
                    "language": result.language,
                    "cleaner": result.cleaner,
                    # Which model produced the text, when the provider has a chain. The
                    # interface names the model that answered, not the one requested, so
                    # a fallback is never silent.
                    "model": getattr(cleaner, "answered_with", None),
                    "used_fallback": False,
                    # Measured, not estimated. An interface that shows a latency must
                    # take it from here; there is no other source for one.
                    "timings": _timings(
                        result.transcribe_seconds, result.cleanup_seconds
                    ),
                },
                ensure_ascii=False,
            )
        )
    else:
        print(result.final_text)
    if args.copy:
        try:
            copy_text(result.final_text)
        except VoiceFlowError as exc:
            print(str(exc), file=sys.stderr)
            return 1
    return 0


def _distill(args: argparse.Namespace) -> int:
    store = DistillationStore()
    action = args.distill_action

    try:
        if action == "list":
            pairs = store.load_all()
            counts = store.count_by_mode()
            print(f"Distillation Dataset: {len(pairs)} total pair(s)")
            # The store holds dictated text, so its location is part of the answer.
            print(f"  file: {store.path}")
            for mode, count in counts.items():
                print(f"  [{mode}]: {count} pair(s)")
            if pairs:
                print("\nRecent pair(s):")
                for p in pairs[-3:]:
                    print(f"  [{p.mode.upper()} via {p.cleaner}]")
                    print(f"    Raw:     {p.raw_text}")
                    print(f"    Cleaned: {p.cleaned_text}")
            return 0

        if action == "record":
            pair = store.record(
                raw_text=args.raw,
                cleaned_text=args.cleaned,
                mode=args.mode,
                cleaner=args.cleaner,
                model=args.model,
            )
            print(f"Recorded distillation pair [{pair.mode}]: {pair.cleaned_text}")
            return 0

        if action == "modelfile":
            mode = None if args.mode == "all" else args.mode
            pairs = store.load_all(mode=mode)
            content = build_modelfile(
                base_model=args.base_model,
                mode=args.mode,
                pairs=pairs,
            )
            if args.out:
                args.out.parent.mkdir(parents=True, exist_ok=True)
                args.out.write_text(content, encoding="utf-8")
                print(f"Modelfile written to: {args.out}")
            else:
                print(content)
            return 0

        if action == "create":
            mode = None if args.mode == "all" else args.mode
            pairs = store.load_all(mode=mode)
            content = build_modelfile(
                base_model=args.base_model,
                mode=args.mode,
                pairs=pairs,
            )
            print(f"Building and registering '{args.name}' with Ollama at {args.ollama_url}...")
            success = create_ollama_model(
                model_name=args.name,
                modelfile_content=content,
                base_url=args.ollama_url,
            )
            if success:
                print(f"✓ Successfully created model '{args.name}' in Ollama.")
                return 0
            print(f"Failed to create model '{args.name}'.", file=sys.stderr)
            return 1

        if action == "export":
            count = store.export_jsonl(args.to, mode=args.mode)
            print(f"Exported {count} distillation pair(s) to: {args.to}")
            return 0

        if action == "clear":
            if not args.yes:
                print(
                    f"{store.path} holds dictated text. Repeat with --yes to delete "
                    "every stored pair; export first if you want to keep them.",
                    file=sys.stderr,
                )
                return 1
            removed = store.clear()
            print(f"Deleted {removed} distillation pair(s) and removed {store.path}.")
            return 0

    except (VoiceFlowError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


def _snippet(args: argparse.Namespace) -> int:
    store = SnippetStore()
    action = args.snippet_action

    try:
        if action == "list":
            snippets = store.load()
            if not snippets:
                print("No voice snippets registered.")
                return 0
            print(f"Voice Snippets: {len(snippets)} active macro(s)")
            for s in snippets:
                desc = f" ({s.description})" if s.description else ""
                print(f"  [{s.trigger}]{desc} ->")
                for line in s.expansion.splitlines():
                    print(f"      {line}")
            return 0

        if action == "add":
            snippet = store.add(
                trigger=args.trigger,
                expansion=args.expansion,
                description=args.description,
            )
            print(f"Added voice snippet [{snippet.trigger}].")
            return 0

        if action == "delete":
            deleted = store.delete(args.trigger)
            if deleted:
                print(f"Deleted voice snippet [{args.trigger}].")
                return 0
            print(f"Snippet [{args.trigger}] not found.", file=sys.stderr)
            return 1

        if action == "export":
            count = store.export_json(args.to)
            print(f"Exported {count} voice snippet(s) to: {args.to}")
            return 0

        if action == "import":
            count = store.import_json(args.from_path)
            print(f"Imported {count} voice snippet(s) from: {args.from_path}")
            return 0

    except (VoiceFlowError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    handlers = {
        "doctor": _doctor,
        "provider": _provider,
        "memory": _memory,
        "correct": _correct,
        "forget": _forget,
        "export": _export,
        "practice": _practice,
        "process": _process,
        "distill": _distill,
        "snippet": _snippet,
    }
    return handlers[args.command](args)


def entrypoint() -> None:
    raise SystemExit(main())
