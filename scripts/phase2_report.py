#!/usr/bin/env python3
"""Build the private Phase 2 accuracy and latency report."""

from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import unicodedata
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence


DEFAULT_DIRECTORY = Path.home() / "Library/Application Support/sanblue.voiceflow"
DEFAULT_CORPUS = DEFAULT_DIRECTORY / "phase2-corpus.local.json"
DEFAULT_RESULTS = DEFAULT_DIRECTORY / "phase2-results.local.jsonl"
DEFAULT_REPORT = DEFAULT_DIRECTORY / "phase2-report.local.md"
EXPECTED_RECORDINGS = 20


def normalize_words(text: str) -> list[str]:
    normalized = unicodedata.normalize("NFKC", text).casefold()
    normalized = re.sub(r"[^\w]+", " ", normalized, flags=re.UNICODE)
    return normalized.split()


def word_error_rate(reference: str, hypothesis: str) -> float:
    reference_words = normalize_words(reference)
    hypothesis_words = normalize_words(hypothesis)
    if not reference_words:
        return 0.0 if not hypothesis_words else 1.0

    previous = list(range(len(hypothesis_words) + 1))
    for row, reference_word in enumerate(reference_words, start=1):
        current = [row]
        for column, hypothesis_word in enumerate(hypothesis_words, start=1):
            substitution = previous[column - 1] + (
                reference_word != hypothesis_word
            )
            insertion = current[column - 1] + 1
            deletion = previous[column] + 1
            current.append(min(substitution, insertion, deletion))
        previous = current
    return previous[-1] / len(reference_words)


def percentile(values: Sequence[float], proportion: float) -> float:
    ordered = sorted(values)
    if not ordered:
        raise ValueError("At least one value is required.")
    position = (len(ordered) - 1) * proportion
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def load_results(path: Path) -> list[dict[str, Any]]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def markdown_cell(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def build_report(
    corpus: list[dict[str, Any]],
    results: list[dict[str, Any]],
    confirmed_apps: set[str],
) -> str:
    if len(corpus) != EXPECTED_RECORDINGS:
        raise ValueError(f"The fixed corpus must contain {EXPECTED_RECORDINGS} items.")
    if len(results) != EXPECTED_RECORDINGS:
        raise ValueError(
            f"Expected {EXPECTED_RECORDINGS} results, found {len(results)}."
        )

    rows: list[dict[str, Any]] = []
    for expected_sequence, (sample, result) in enumerate(
        zip(corpus, results, strict=True),
        start=1,
    ):
        if sample.get("id") != expected_sequence:
            raise ValueError(
                f"Corpus item {expected_sequence} is missing or out of order."
            )
        if result.get("sequence") != expected_sequence:
            raise ValueError(
                f"Result sequence {expected_sequence} is missing or out of order."
            )
        rows.append(
            {
                "sequence": expected_sequence,
                "app": sample["target_app"],
                "category": sample["category"],
                "reference": sample["reference"],
                "raw": result["raw_text"],
                "personalized": result.get(
                    "personalized_text", result["raw_text"]
                ),
                "final": result["final_text"],
                "latency": float(result["latency_seconds"]),
                "raw_wer": word_error_rate(sample["reference"], result["raw_text"]),
                "personalized_wer": word_error_rate(
                    sample["reference"],
                    result.get("personalized_text", result["raw_text"]),
                ),
                "final_wer": word_error_rate(sample["reference"], result["final_text"]),
                "fallback": bool(
                    result.get("used_fallback", result.get("used_raw_fallback", False))
                ),
            }
        )

    measured_latency_rows = rows[1:]
    latencies = [row["latency"] for row in measured_latency_rows]
    raw_wers = [row["raw_wer"] for row in rows]
    personalized_wers = [row["personalized_wer"] for row in rows]
    final_wers = [row["final_wer"] for row in rows]
    target_apps = list(dict.fromkeys(row["app"] for row in rows))

    lines = [
        "# VoiceFlow Phase 2 Acceptance Report",
        "",
        f"- Generated: {datetime.now(timezone.utc).isoformat(timespec='seconds')}",
        f"- Completed recordings: {len(rows)}/{EXPECTED_RECORDINGS}",
        "- Latency window: recordings 2–20; recording 1 is the warm-up",
        f"- Release-to-result p50: {statistics.median(latencies):.2f} seconds",
        f"- Release-to-result p95: {percentile(latencies, 0.95):.2f} seconds",
        f"- Mean raw WER: {statistics.mean(raw_wers):.1%}",
        f"- Mean personalized WER: {statistics.mean(personalized_wers):.1%}",
        f"- Mean cleaned WER: {statistics.mean(final_wers):.1%}",
        f"- Safe fallbacks: {sum(row['fallback'] for row in rows)}",
        "",
        "## Clipboard delivery",
        "",
    ]
    for app in target_apps:
        state = "confirmed" if app in confirmed_apps else "manual confirmation pending"
        lines.append(f"- {app}: {state}")

    lines.extend(
        [
            "",
            "## Per-sample evidence",
            "",
            "| # | App | Category | Latency | Raw WER | Personalized WER | "
            "Cleaned WER | Reference | Raw | Personalized | Cleaned |",
            "|---:|---|---|---:|---:|---:|---:|---|---|---|---|",
        ]
    )
    for row in rows:
        lines.append(
            f"| {row['sequence']} | {markdown_cell(row['app'])} | "
            f"{markdown_cell(row['category'])} | {row['latency']:.2f}s | "
            f"{row['raw_wer']:.1%} | {row['personalized_wer']:.1%} | "
            f"{row['final_wer']:.1%} | "
            f"{markdown_cell(row['reference'])} | {markdown_cell(row['raw'])} | "
            f"{markdown_cell(row['personalized'])} | "
            f"{markdown_cell(row['final'])} |"
        )
    lines.append("")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--results", type=Path, default=DEFAULT_RESULTS)
    parser.add_argument("--output", type=Path, default=DEFAULT_REPORT)
    parser.add_argument(
        "--confirmed-app",
        action="append",
        default=[],
        help="Target app whose clipboard delivery the owner confirmed.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    corpus = load_json(args.corpus)
    results = load_results(args.results)
    report = build_report(corpus, results, set(args.confirmed_app))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(report, encoding="utf-8")
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
