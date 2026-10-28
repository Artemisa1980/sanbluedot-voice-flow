#!/usr/bin/env python3
"""Replay a saved acceptance run through the engine under different settings.

The point is comparability. Recording again would change the speaker as well as the
setting, so nothing could be attributed. Replaying the same audio isolates the change.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from phase2_report import DEFAULT_CORPUS, DEFAULT_RESULTS, percentile, word_error_rate

from sanbluedot_voiceflow.cleaners import (
    CLEANER_NAMES,
    DEFAULT_APPLE_BINARY,
    DEFAULT_GEMINI_MODEL,
    build_cleaner,
)
from sanbluedot_voiceflow.errors import CleanupFailed, VoiceFlowError
from sanbluedot_voiceflow.memory import (
    PROMPT_CHAR_BUDGET,
    CorrectionStore,
    build_initial_prompt,
    load_vocabulary,
)
from sanbluedot_voiceflow.pipeline import DictationPipeline
from sanbluedot_voiceflow.transcribers import ParakeetTranscriber, WhisperCppTranscriber

REPO_ROOT = Path(__file__).resolve().parent.parent
PARAKEET_MODELS = REPO_ROOT / "models/fluidaudio/parakeet-ultra"


def load_samples(
    corpus_path: Path,
    results_path: Path,
    *,
    require_complete: bool = False,
) -> list[dict[str, Any]]:
    corpus = json.loads(corpus_path.read_text(encoding="utf-8"))
    if not isinstance(corpus, list):
        raise ValueError("The corpus top level must be a list.")
    results: list[dict[str, Any]] = [
        json.loads(line)
        for line in results_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    for entry in corpus:
        if not isinstance(entry, dict):
            raise ValueError("Every corpus item must be an object.")
        if type(entry.get("id")) is not int or int(entry["id"]) < 1:
            raise ValueError("Every corpus item needs a positive integer id.")
        if not isinstance(entry.get("reference"), str):
            raise ValueError("Every corpus item needs a text reference.")
        if "category" in entry and not isinstance(entry["category"], str):
            raise ValueError("Corpus categories must be text.")
    for item in results:
        if not isinstance(item, dict):
            raise ValueError("Every result must be an object.")
        if type(item.get("sequence")) is not int or int(item["sequence"]) < 1:
            raise ValueError("Every result needs a positive integer sequence.")
        audio_value = item.get("audio_file")
        if audio_value is not None and not isinstance(audio_value, str):
            raise ValueError("Result audio_file values must be text or null.")

    corpus_ids = [entry["id"] for entry in corpus]
    result_ids = [item["sequence"] for item in results]
    if len(set(corpus_ids)) != len(corpus_ids):
        raise ValueError("The corpus contains duplicate ids.")
    if len(set(result_ids)) != len(result_ids):
        raise ValueError("The results contain duplicate sequence values.")
    unknown = set(result_ids) - set(corpus_ids)
    if unknown:
        raise ValueError(
            f"The results contain unknown sequence values: {sorted(unknown)}"
        )
    by_sequence = {item["sequence"]: item for item in results}

    samples: list[dict[str, Any]] = []
    missing = 0
    results_directory = results_path.parent.resolve()
    seen_audio: set[Path] = set()
    for entry in corpus:
        result = by_sequence.get(entry["id"])
        audio = result.get("audio_file") if result else None
        if not audio:
            missing += 1
            continue
        relative_audio = Path(audio)
        if relative_audio.is_absolute():
            raise ValueError(f"Audio path must be relative: {audio}")
        candidate = (results_directory / relative_audio).resolve()
        try:
            candidate.relative_to(results_directory)
        except ValueError as exc:
            raise ValueError(f"Audio path escapes the results directory: {audio}") from exc
        if candidate in seen_audio:
            raise ValueError(f"More than one result points to the same audio: {audio}")
        seen_audio.add(candidate)
        if not candidate.is_file():
            missing += 1
            continue
        samples.append(
            {
                "id": entry["id"],
                "category": entry.get("category", "all"),
                "reference": entry["reference"],
                "audio": candidate,
            }
        )
    if missing:
        detail = f"{missing} corpus items have no saved audio."
        if require_complete:
            raise ValueError(detail)
        print(f"note: {detail} They were skipped.")
    return samples


def build_pipeline(args: argparse.Namespace) -> DictationPipeline:
    corrections = () if (args.no_memory or args.no_corrections) else tuple(CorrectionStore().load())
    raw_vocab = () if (args.no_memory or args.no_vocab_prompt) else tuple(load_vocabulary())
    prompt = (
        ""
        if (args.no_memory or args.no_vocab_prompt)
        else build_initial_prompt(raw_vocab, args.prompt_budget)
    )
    cleaner = build_cleaner(
        args.cleaner,
        gemini_model=args.gemini_model,
        apple_binary=getattr(args, "apple_bin", DEFAULT_APPLE_BINARY),
    )
    if getattr(args, "transcriber", "whisper") == "parakeet":
        # The same helper the application runs; Parakeet reads no vocabulary prompt.
        transcriber = ParakeetTranscriber(model_dir=args.parakeet_models, binary=args.parakeet_bin)
        return DictationPipeline(
            transcriber=transcriber,
            cleaner=cleaner,
            corrections=corrections,
            vocabulary=raw_vocab,
        )
    transcriber = WhisperCppTranscriber(
        model_path=args.whisper_model,
        binary=args.whisper_bin,
        language=args.language,
        initial_prompt=prompt,
        threads=args.threads,
        beam_size=args.beam_size,
    )
    return DictationPipeline(
        transcriber=transcriber,
        cleaner=cleaner,
        corrections=corrections,
        vocabulary=raw_vocab,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--results", type=Path, default=DEFAULT_RESULTS)
    parser.add_argument("--transcriber", default="whisper", choices=["whisper", "parakeet"])
    parser.add_argument("--whisper-model", type=Path)
    parser.add_argument("--parakeet-bin", default="voiceflow-parakeet")
    parser.add_argument("--parakeet-models", type=Path, default=PARAKEET_MODELS)
    parser.add_argument("--whisper-bin", default="whisper-cli")
    parser.add_argument("--language", default="auto", choices=["auto", "en", "es"])
    parser.add_argument("--cleaner", default="literal", choices=list(CLEANER_NAMES))
    parser.add_argument("--gemini-model", default=DEFAULT_GEMINI_MODEL)
    parser.add_argument(
        "--apple-bin",
        default=DEFAULT_APPLE_BINARY,
        help="The helper that reaches Apple's on-device model, for --cleaner apple.",
    )
    parser.add_argument("--no-vocab-prompt", action="store_true")
    parser.add_argument("--prompt-budget", type=int, default=PROMPT_CHAR_BUDGET)
    parser.add_argument("--threads", type=int)
    parser.add_argument("--beam-size", type=int)
    parser.add_argument("--no-memory", action="store_true")
    parser.add_argument("--no-corrections", action="store_true")
    parser.add_argument(
        "--require-complete",
        action="store_true",
        help=(
            "Fail unless every corpus item has unique contained audio and processes "
            "without an engine error or cleanup fallback."
        ),
    )
    parser.add_argument("--label", default="replay", help="Name this configuration.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    transcriber_name = getattr(args, "transcriber", "whisper")
    if transcriber_name == "whisper" and args.whisper_model is None:
        print("Whisper needs --whisper-model.", file=sys.stderr)
        return 1
    try:
        samples = load_samples(
            args.corpus,
            args.results,
            require_complete=args.require_complete,
        )
    except (KeyError, TypeError, ValueError, json.JSONDecodeError, OSError) as exc:
        print(f"Cannot replay this run: {exc}", file=sys.stderr)
        return 1
    if not samples:
        print("No saved audio to replay.", file=sys.stderr)
        return 1

    pipeline = build_pipeline(args)
    raw_wers: list[float] = []
    personalized_wers: list[float] = []
    final_wers: list[float] = []
    durations: list[float] = []
    by_category: dict[str, list[float]] = {}
    failures = 0
    fallbacks = 0

    for sample in samples:
        started = time.monotonic()
        try:
            result = pipeline.process(sample["audio"])
            raw_text = result.raw_text
            personalized_text = result.personalized_text
            final_text = result.final_text
        except CleanupFailed as exc:
            fallbacks += 1
            raw_text = exc.raw_text
            personalized_text = final_text = exc.fallback_text
        except VoiceFlowError as exc:
            failures += 1
            print(f"  {sample['id']:>2}: FAILED — {exc}", file=sys.stderr)
            continue
        durations.append(time.monotonic() - started)
        raw_wer = word_error_rate(sample["reference"], raw_text)
        personalized_wer = word_error_rate(sample["reference"], personalized_text)
        raw_wers.append(raw_wer)
        personalized_wers.append(personalized_wer)
        final_wers.append(word_error_rate(sample["reference"], final_text))
        by_category.setdefault(sample["category"], []).append(personalized_wer)

    if not raw_wers:
        print("Every sample failed.", file=sys.stderr)
        return 1

    print(f"\n{args.label}: {len(raw_wers)} samples replayed, {failures} failed")
    print(f"  safe fallbacks  {fallbacks}")
    print(f"  transcriber    {transcriber_name}")
    print(f"  cleaner        {args.cleaner}")
    print(
        "  vocab prompt   "
        + (
            "none, Parakeet reads no prompt"
            if transcriber_name == "parakeet"
            else "off"
            if (args.no_memory or args.no_vocab_prompt)
            else f"on, {args.prompt_budget} chars"
        )
    )
    print(f"  corrections    {'off' if (args.no_memory or args.no_corrections) else 'on'}")
    print(f"  threads/beam   {args.threads or 'default'} / {args.beam_size or 'default'}")
    print(f"  mean raw WER      {statistics.mean(raw_wers):.1%}")
    print(f"  mean personalized WER {statistics.mean(personalized_wers):.1%}")
    print(f"  mean cleaned WER  {statistics.mean(final_wers):.1%}")
    stage = "engine" if args.cleaner == "literal" else "engine+cleaner"
    print(f"  {stage} p50/p95  {statistics.median(durations):.2f}s / "
          f"{percentile(durations, 0.95):.2f}s")
    if len(by_category) > 1:
        print("  personalized WER by category")
        for category, wers in sorted(by_category.items(),
                                     key=lambda kv: statistics.mean(kv[1])):
            print(f"    {category:12} {len(wers):>2}  {statistics.mean(wers):6.1%}")
    if args.require_complete and (failures or fallbacks):
        print(
            "Replay is incomplete because "
            f"{failures} sample(s) failed and {fallbacks} used a safe fallback.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
