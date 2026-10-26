#!/usr/bin/env python3
"""Measure what a cleanup model actually changes, on one fixed recorded corpus.

Aggregate word error rate cannot answer whether cleanup is worth running. It folds
punctuation away before comparing, so the one thing conservative cleanup is supposed to
add is invisible to it, while any word the model invented is already blocked by the
output guard before the text is delivered.

This gate separates the two questions. Every sample is transcribed once, so recognition
is identical across cleaners and only the cleaner varies. Each candidate then faces the
real output guard, and the report states how often the guard refused the candidate, what
the accepted output did to the words, and whether its punctuation moved toward or away
from the reference the speaker read.

The gate is provider-neutral by construction: a cloud adapter implements the same
`clean(text, language_hint)` contract and faces this identical corpus and guard.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from phase2_report import DEFAULT_CORPUS, DEFAULT_RESULTS, normalize_words
from replay import load_samples

from sanbluedot_voiceflow.cleaners import (
    CLEANER_NAMES,
    DEFAULT_APPLE_BINARY,
    DEFAULT_GEMINI_MODEL,
    LiteralCleaner,
    build_cleaner,
)
from sanbluedot_voiceflow.errors import CleanupError, VoiceFlowError
from sanbluedot_voiceflow.memory import (
    PROMPT_CHAR_BUDGET,
    CorrectionStore,
    build_initial_prompt,
    load_vocabulary,
)
from sanbluedot_voiceflow.output_guard import (
    _REMOVABLE_FILLERS,
    guard_conservative_cleanup,
)
from sanbluedot_voiceflow.pipeline import DictationPipeline
from sanbluedot_voiceflow.transcribers import WhisperCppTranscriber


MARKS = ".,;:!?"


def annotate(text: str) -> list[tuple[str, str]]:
    """Pair each word with the punctuation mark written immediately after it.

    Punctuation is a property of the boundary that follows a word, so it is stored on
    that word rather than as a token of its own. A word followed by nothing carries the
    empty mark, which keeps present and absent punctuation directly comparable.
    """
    annotated: list[tuple[str, str]] = []
    for chunk in unicodedata.normalize("NFKC", text).split():
        stripped = chunk.rstrip(MARKS + '"\')]}»')
        # Only the marks after the word count: the dot inside `3.5` or `example.com`
        # was read as punctuation and moved the F1 that decides a verdict (D-100).
        mark = ""
        for character in reversed(chunk[len(stripped):]):
            if character in MARKS:
                mark = character
                break
        words = normalize_words(stripped)
        if not words:
            continue
        for word in words[:-1]:
            annotated.append((word, ""))
        annotated.append((words[-1], mark))
    return annotated


def align(reference: list[str], hypothesis: list[str]) -> list[tuple[int, int]]:
    """Return index pairs for words the two sequences share, in order.

    Levenshtein alignment rather than position matching: a single dropped word would
    otherwise shift every later word and report the whole tail as different.
    """
    rows, columns = len(reference), len(hypothesis)
    costs = [[0] * (columns + 1) for _ in range(rows + 1)]
    for row in range(rows + 1):
        costs[row][0] = row
    for column in range(columns + 1):
        costs[0][column] = column
    for row in range(1, rows + 1):
        for column in range(1, columns + 1):
            substitution = costs[row - 1][column - 1] + (
                reference[row - 1] != hypothesis[column - 1]
            )
            costs[row][column] = min(
                substitution, costs[row - 1][column] + 1, costs[row][column - 1] + 1
            )

    pairs: list[tuple[int, int]] = []
    row, column = rows, columns
    while row > 0 and column > 0:
        if (
            reference[row - 1] == hypothesis[column - 1]
            and costs[row][column] == costs[row - 1][column - 1]
        ):
            pairs.append((row - 1, column - 1))
            row, column = row - 1, column - 1
        elif costs[row][column] == costs[row - 1][column - 1] + 1:
            row, column = row - 1, column - 1
        elif costs[row][column] == costs[row - 1][column] + 1:
            row -= 1
        else:
            column -= 1
    pairs.reverse()
    return pairs


@dataclass(frozen=True, slots=True)
class Punctuation:
    matched: int
    hypothesis_total: int
    reference_total: int

    @property
    def precision(self) -> float:
        return self.matched / self.hypothesis_total if self.hypothesis_total else 0.0

    @property
    def recall(self) -> float:
        return self.matched / self.reference_total if self.reference_total else 0.0

    @property
    def f1(self) -> float:
        precision, recall = self.precision, self.recall
        if not precision or not recall:
            return 0.0
        return 2 * precision * recall / (precision + recall)


def punctuation_agreement(reference: str, hypothesis: str) -> Punctuation:
    """Compare punctuation only where both texts agree on the word it follows.

    A mark after a word the engine never recovered is excluded from the score on both
    sides, so recognition error cannot be read as a punctuation result. Totals therefore
    cover recovered words only, which is what makes the before and after figures
    comparable.
    """
    reference_pairs = annotate(reference)
    hypothesis_pairs = annotate(hypothesis)
    matched = reference_total = hypothesis_total = 0
    for reference_index, hypothesis_index in align(
        [word for word, _ in reference_pairs],
        [word for word, _ in hypothesis_pairs],
    ):
        reference_mark = reference_pairs[reference_index][1]
        hypothesis_mark = hypothesis_pairs[hypothesis_index][1]
        reference_total += bool(reference_mark)
        hypothesis_total += bool(hypothesis_mark)
        if reference_mark and reference_mark == hypothesis_mark:
            matched += 1
    return Punctuation(
        matched=matched,
        hypothesis_total=hypothesis_total,
        reference_total=reference_total,
    )


def word_difference(source: str, candidate: str) -> list[str]:
    """Words the candidate changed that removing an unambiguous filler cannot explain."""
    source_words = normalize_words(source)
    candidate_words = normalize_words(candidate)
    kept = [word for word in source_words if word not in _REMOVABLE_FILLERS]
    if candidate_words == source_words or candidate_words == kept:
        return []
    return [
        word
        for word in source_words
        if source_words.count(word) != candidate_words.count(word)
        and word not in _REMOVABLE_FILLERS
    ] or ["word order changed"]


def transcribe_corpus(args: argparse.Namespace, samples: list[dict[str, Any]]) -> list[dict[str, Any]]:
    corrections = () if args.no_memory else tuple(CorrectionStore().load())
    prompt = "" if args.no_memory else build_initial_prompt(load_vocabulary(), PROMPT_CHAR_BUDGET)
    pipeline = DictationPipeline(
        transcriber=WhisperCppTranscriber(
            model_path=args.whisper_model,
            binary=args.whisper_bin,
            language=args.language,
            initial_prompt=prompt,
        ),
        cleaner=LiteralCleaner(),
        corrections=corrections,
    )
    transcribed: list[dict[str, Any]] = []
    for sample in samples:
        try:
            result = pipeline.process(sample["audio"])
        except VoiceFlowError as exc:
            print(f"  {sample['id']:>2}: transcription failed — {exc}", file=sys.stderr)
            continue
        transcribed.append(
            {
                **sample,
                "personalized": result.personalized_text,
                "detected_language": result.language,
            }
        )
    return transcribed


def evaluate(cleaner: Any, transcribed: list[dict[str, Any]]) -> dict[str, Any]:
    accepted = 0
    rejected: list[str] = []
    violations: list[str] = []
    durations: list[float] = []
    before = Punctuation(0, 0, 0)
    after = Punctuation(0, 0, 0)
    changed_samples = 0

    for sample in transcribed:
        source = sample["personalized"]
        baseline = punctuation_agreement(sample["reference"], source)
        before = Punctuation(
            before.matched + baseline.matched,
            before.hypothesis_total + baseline.hypothesis_total,
            before.reference_total + baseline.reference_total,
        )
        started = time.monotonic()
        try:
            candidate = guard_conservative_cleanup(
                source,
                cleaner.clean(source, language_hint=sample["detected_language"]),
            )
        except CleanupError as exc:
            rejected.append(f"{sample['id']}: {exc}")
            candidate = source
        except VoiceFlowError as exc:
            rejected.append(f"{sample['id']}: {exc}")
            candidate = source
        else:
            accepted += 1
            differences = word_difference(source, candidate)
            if differences:
                violations.append(f"{sample['id']}: {differences[0]}")
            if candidate.strip() != source.strip():
                changed_samples += 1
        durations.append(time.monotonic() - started)
        delivered = punctuation_agreement(sample["reference"], candidate)
        after = Punctuation(
            after.matched + delivered.matched,
            after.hypothesis_total + delivered.hypothesis_total,
            after.reference_total + delivered.reference_total,
        )

    return {
        "samples": len(transcribed),
        "accepted": accepted,
        "rejected": rejected,
        "violations": violations,
        "changed": changed_samples,
        "before": before,
        "after": after,
        "median_seconds": statistics.median(durations) if durations else 0.0,
    }


def verdict(report: dict[str, Any]) -> tuple[str, str]:
    """PASS only when cleanup measurably helps, never merely because nothing broke.

    Punctuation is scored against what the speaker actually wrote, so a corpus whose
    references carry no punctuation cannot charge a cleaner for inventing marks. That
    corpus is refused rather than silently scored, because the blind spot would read as
    a clean result.
    """
    if report["violations"]:
        return "FAIL", "accepted output changed words the guard was expected to block"
    if not report["before"].reference_total:
        return (
            "INVALID",
            "the corpus references carry no punctuation to measure cleanup against",
        )
    before_f1 = report["before"].f1
    after_f1 = report["after"].f1
    if after_f1 < before_f1 - 1e-9:
        return "FAIL", "punctuation moved away from the reference"
    if after_f1 > before_f1 + 1e-9:
        return "PASS", "punctuation moved toward the reference"
    return (
        "CONDITIONAL",
        "delivered text is no closer to the reference than the engine transcript",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--results", type=Path, default=DEFAULT_RESULTS)
    parser.add_argument("--whisper-model", type=Path, required=True)
    parser.add_argument("--whisper-bin", default="whisper-cli")
    parser.add_argument("--language", default="auto", choices=["auto", "en", "es"])
    parser.add_argument("--cleaner", default="apple", choices=list(CLEANER_NAMES))
    parser.add_argument("--gemini-model", default=DEFAULT_GEMINI_MODEL)
    parser.add_argument(
        "--apple-bin",
        default=DEFAULT_APPLE_BINARY,
        help="The helper that reaches Apple's on-device model, for --cleaner apple.",
    )
    parser.add_argument("--no-memory", action="store_true")
    parser.add_argument("--label", default="cleaner gate")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        samples = load_samples(args.corpus, args.results)
    except (KeyError, TypeError, ValueError, json.JSONDecodeError, OSError) as exc:
        print(f"Cannot read this corpus: {exc}", file=sys.stderr)
        return 1
    if not samples:
        print("No saved audio to evaluate.", file=sys.stderr)
        return 1

    transcribed = transcribe_corpus(args, samples)
    if not transcribed:
        print("Every sample failed to transcribe.", file=sys.stderr)
        return 1

    cleaner = build_cleaner(
        args.cleaner,
        gemini_model=args.gemini_model,
        apple_binary=args.apple_bin,
    )
    report = evaluate(cleaner, transcribed)
    outcome, reason = verdict(report)

    print(f"\n{args.label}: {report['samples']} samples, cleaner {args.cleaner}")
    print(f"  accepted by the guard   {report['accepted']}/{report['samples']}")
    print(f"  text actually changed   {report['changed']}")
    print(f"  median cleanup time     {report['median_seconds']:.2f}s")
    print(
        "  punctuation F1          "
        f"{report['before'].f1:.1%} engine -> {report['after'].f1:.1%} delivered"
    )
    print(
        "    precision / recall    "
        f"{report['before'].precision:.1%} / {report['before'].recall:.1%} -> "
        f"{report['after'].precision:.1%} / {report['after'].recall:.1%}"
    )
    # Raw counts beside the rates: on a short corpus a single recovered mark moves the
    # rate by several points, and a verdict read without them overstates the result.
    print(
        "    marks matched         "
        f"{report['before'].matched}/{report['before'].reference_total} -> "
        f"{report['after'].matched}/{report['after'].reference_total} reference marks, "
        f"{report['before'].hypothesis_total} -> {report['after'].hypothesis_total} placed"
    )
    for rejection in report["rejected"]:
        print(f"  rejected  {rejection}")
    for violation in report["violations"]:
        print(f"  VIOLATION {violation}")
    print(f"  verdict: {outcome} — {reason}")
    return 0 if outcome in ("PASS", "CONDITIONAL") else 1


if __name__ == "__main__":
    raise SystemExit(main())
