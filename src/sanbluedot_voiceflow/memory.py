"""Confirmed local vocabulary and correction memory.

Two layers with different jobs. Vocabulary is preventive: the terms are handed to
the speech engine before it listens, so a rare word is recognized instead of guessed.
Corrections are reparative: a confirmed pair rewrites what the engine still gets
wrong. Neither layer trains a model; both are plain local files the user owns.
"""

import json
import os
import re
import sys
import uuid
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


def write_json_atomically(path: Path, payload: object) -> None:
    """Write through a temporary file in the same directory, then rename.

    `write_text` truncates first, so an interruption leaves a half-written file. That
    file then fails to parse on every later read, and a corrupted correction store
    blocks dictation entirely. `os.replace` is atomic on the same filesystem.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        temporary.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


@contextmanager
def exclusive_file_lock(path: Path) -> Iterator[None]:
    """Serialize one store's read-modify-write cycle across local processes."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_name(f".{path.name}.lock")
    with lock_path.open("a+b") as handle:
        if os.name == "nt":
            import msvcrt

            handle.seek(0, os.SEEK_END)
            if handle.tell() == 0:
                handle.write(b"\0")
                handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
            try:
                yield
            finally:
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def quarantine_file(path: Path, kind: str, error: object) -> None:
    """Preserve one unusable personal file under a dated name and report it."""
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    quarantine = path.with_name(f"{path.name}.corrupt-{stamp}")
    try:
        os.replace(path, quarantine)
    except OSError:
        quarantine = path
    print(
        f"{kind} could not be read ({error}). It was moved to {quarantine.name} and "
        "this run continues without it.",
        file=sys.stderr,
    )


def read_json_or_quarantine(path: Path, kind: str) -> dict[str, object] | None:
    """Return parsed JSON, or move an unreadable file aside and return None.

    Personal memory must never be able to stop the speaker from dictating. A damaged
    file is preserved under a dated name rather than deleted, and the loss is reported.
    """
    if not path.is_file():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("the top-level JSON value is not an object")
        return payload
    except (json.JSONDecodeError, UnicodeDecodeError, OSError, ValueError) as exc:
        quarantine_file(path, kind, exc)
        return None


SCHEMA_VERSION = 1

DEFAULT_DIRECTORY = Path.home() / "Library/Application Support/sanblue.voiceflow"
DEFAULT_VOCABULARY = DEFAULT_DIRECTORY / "vocabulary.local.txt"
DEFAULT_CORRECTIONS = DEFAULT_DIRECTORY / "corrections.local.json"

# whisper.cpp accepts at most n_text_ctx/2 tokens of initial prompt, about 224 for
# the multilingual models. Mixed Spanish and English averages under three characters
# per token, so this budget stays clear of the cap without tokenizing here.
PROMPT_CHAR_BUDGET = 600


def schema_version_is_supported(
    payload: dict[str, object],
    path: Path,
    kind: str,
) -> bool:
    """Accept schema 1 and legacy unversioned data; quarantine incompatible data."""
    version = payload.get("schema_version", SCHEMA_VERSION)
    if type(version) is int and version == SCHEMA_VERSION:
        return True
    quarantine_file(path, kind, f"unsupported schema version: {version!r}")
    return False


def load_vocabulary(path: Path = DEFAULT_VOCABULARY) -> list[str]:
    """Read the term list. File order is priority order; the prompt fills from the top."""
    if not path.is_file():
        return []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (UnicodeDecodeError, OSError) as exc:
        quarantine_file(path, "The vocabulary store", exc)
        return []
    terms: list[str] = []
    seen: set[str] = set()
    for line in lines:
        term = line.strip()
        if not term or term.startswith("#") or term.casefold() in seen:
            continue
        seen.add(term.casefold())
        terms.append(term)
    return terms


def add_vocabulary_term(term: str, path: Path = DEFAULT_VOCABULARY) -> bool:
    """Append one term. False when it is already there, in any case.

    File order is priority order and the prompt fills from the top, so a new term lands
    last: past the budget it is stored and unread, which the Words section says.
    """
    term = term.strip()
    if not term or "\n" in term:
        raise ValueError("A vocabulary term is one line of text.")
    with exclusive_file_lock(path):
        existing = load_vocabulary(path)
        if term.casefold() in {item.casefold() for item in existing}:
            return False
        lines = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
        _write_lines_atomically(path, lines + [term])
    return True


def remove_vocabulary_term(term: str, path: Path = DEFAULT_VOCABULARY) -> bool:
    """Remove one term, keeping every other line and comment in its place."""
    wanted = term.strip().casefold()
    if not wanted or not path.is_file():
        return False
    with exclusive_file_lock(path):
        lines = path.read_text(encoding="utf-8").splitlines()
        kept = [line for line in lines if line.strip().casefold() != wanted]
        if len(kept) == len(lines):
            return False
        _write_lines_atomically(path, kept)
    return True


def _write_lines_atomically(path: Path, lines: Sequence[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        temporary.write_text("".join(f"{line}\n" for line in lines), encoding="utf-8")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def build_initial_prompt(
    terms: Sequence[str],
    char_budget: int = PROMPT_CHAR_BUDGET,
) -> str:
    """Join as many leading terms as the budget allows into a whisper initial prompt.

    A fixed list of priming terms was appended here to bias mixed Spanish/English
    recognition. Measured against the real store it never reached whisper: 226 personal
    terms already fill 596 of the 600 characters, so every appended term was cut and the
    prompt was byte-identical with the feature on and off. The two tests that covered it
    used two-term fixtures, which is why the budget never bound them. Reviving it means
    prepending rather than appending, which changes what the engine hears and must be
    measured on the fixed corpus with punctuation first — `phase-5-proposal.md`, 8.
    """
    selected: list[str] = []
    used = 0
    for term in terms:
        cost = len(term) + (2 if selected else 0)
        if used + cost > char_budget:
            break
        selected.append(term)
        used += cost
    return ", ".join(selected)


def export_memory(
    destination: Path,
    vocabulary: Path = DEFAULT_VOCABULARY,
    directory: Path = DEFAULT_DIRECTORY,
) -> tuple[Path, dict[str, int]]:
    """Write every piece of local personal memory into one portable file.

    R7 requires local user data to support export, and the product targets two
    computers. Audio is deliberately excluded: recordings are large and are the
    speaker's voice, so they move only by explicit copy.

    Every other store belongs here. Snippets and distillation pairs were absent while
    this function promised "every piece", so a speaker moving to a second machine lost
    both without being told. Each store also has its own export command; this file is
    the one that has to be complete.

    Returns the path and a count per section, so the caller can say what left the
    machine rather than only that something did. R5c allows pairs to leave through an
    explicit export, and this is one — but an export that does not name what it carried
    is not a decision the speaker actually made.

    Every store is addressed under `directory` rather than by its own default. Reading
    the real ones from a test is how a test suite ends up copying the speaker's actual
    sentences into a temporary file, and this function reads five stores.
    """
    # Imported here: both modules import from this one.
    from .practice import PracticeStore
    from .snippets import SnippetStore
    from .distill import DistillationStore

    terms = load_vocabulary(vocabulary)
    corrections = [
        {
            "heard": item.heard,
            "intended": item.intended,
            "confirmed_at": item.confirmed_at,
            **({"source": item.source} if item.source else {}),
        }
        for item in CorrectionStore(directory / "corrections.local.json").load()
    ]
    practice_sessions = PracticeStore(directory / "practice").load()
    snippets = [
        item.to_dict()
        for item in SnippetStore(directory / "snippets.local.json").load()
    ]
    distillation_pairs = [
        pair.to_dict()
        for pair in DistillationStore(directory / "distill_pairs.local.jsonl").load_all()
    ]

    write_json_atomically(
        destination,
        {
            "schema_version": SCHEMA_VERSION,
            "exported_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "vocabulary": terms,
            "corrections": corrections,
            "practice_sessions": practice_sessions,
            "snippets": snippets,
            "distillation_pairs": distillation_pairs,
        },
    )
    counts = {
        "vocabulary": len(terms),
        "corrections": len(corrections),
        "practice_sessions": len(practice_sessions),
        "snippets": len(snippets),
        "distillation_pairs": len(distillation_pairs),
    }
    return destination, counts


# Where a correction was confirmed. "fix" is a History row's FIX, "window" the Words
# section, and the empty string a terminal `vf correct` or a pair stored before sources
# were kept. It is what the Words section filters on; it changes nothing the pair does.
CORRECTION_SOURCES = ("fix", "window")


@dataclass(frozen=True, slots=True)
class Correction:
    heard: str
    intended: str
    confirmed_at: str
    source: str = ""


def _bounded_pattern(heard: str) -> re.Pattern[str]:
    """Match whole words only.

    Gate 3 requires a correction to fix its target without touching unrelated text,
    so a pair can never rewrite a fragment inside a longer word. The boundary is
    dropped at an edge that is not a word character, where `\\b` would never match.
    """
    escaped = re.escape(heard)
    prefix = r"\b" if heard[:1].isalnum() or heard[:1] == "_" else ""
    suffix = r"\b" if heard[-1:].isalnum() or heard[-1:] == "_" else ""
    return re.compile(f"{prefix}{escaped}{suffix}", re.IGNORECASE)


def _match_case(matched: str, replacement: str) -> str:
    if matched.isupper() and len(matched) > 1:
        return replacement.upper()
    if matched[:1].isupper():
        return replacement[:1].upper() + replacement[1:]
    return replacement


def apply_corrections(text: str, corrections: Sequence[Correction]) -> str:
    """Rewrite confirmed mishearings in one pass, longest phrase first.

    One pass matters as the table grows. Applying pairs in sequence lets one pair's
    output land on another pair's trigger, so `sun blue dog -> jin` followed by
    `jin -> Gim` would silently produce Gim. A single scan never re-reads what it
    just wrote.
    """
    usable = [item for item in corrections if item.heard.strip()]
    if not usable:
        return text

    ordered = sorted(usable, key=lambda item: len(item.heard), reverse=True)
    by_key = {item.heard.casefold(): item.intended for item in ordered}
    combined = re.compile(
        "|".join(_bounded_pattern(item.heard).pattern for item in ordered),
        re.IGNORECASE,
    )

    def replace(match: re.Match[str]) -> str:
        matched = match.group(0)
        intended = by_key.get(matched.casefold())
        if intended is None:
            # Whitespace inside a multi-word trigger may differ from the stored form.
            collapsed = " ".join(matched.split()).casefold()
            intended = by_key.get(collapsed)
        return matched if intended is None else _match_case(matched, intended)

    return combined.sub(replace, text)


def correction_needs_global_confirmation(heard: str) -> bool:
    """Single-word triggers rewrite that word everywhere and need a second consent."""
    return len(heard.strip().split()) == 1


class CorrectionStore:
    """Local, inspectable, deletable correction pairs with a versioned schema."""

    def __init__(self, path: Path = DEFAULT_CORRECTIONS) -> None:
        self.path = path

    def load(self) -> list[Correction]:
        payload = read_json_or_quarantine(self.path, "The correction store")
        if payload is None:
            return []
        if not schema_version_is_supported(
            payload,
            self.path,
            "The correction store",
        ):
            return []
        entries = payload.get("corrections", [])
        if not isinstance(entries, list):
            quarantine_file(
                self.path,
                "The correction store",
                "the corrections field is not a list",
            )
            return []
        corrections = []
        for entry in entries:
            # An entry missing either side would rewrite text unpredictably; skip it.
            if not isinstance(entry, dict):
                continue
            heard, intended = entry.get("heard"), entry.get("intended")
            if not isinstance(heard, str) or not isinstance(intended, str):
                continue
            if not heard.strip() or not intended.strip():
                continue
            source = entry.get("source", "")
            corrections.append(
                Correction(
                    heard=heard,
                    intended=intended,
                    confirmed_at=str(entry.get("confirmed_at", "")),
                    source=source if source in CORRECTION_SOURCES else "",
                )
            )
        return corrections

    def add(self, heard: str, intended: str, source: str = "") -> Correction:
        """Store one pair the user confirmed. Re-adding a pair replaces it."""
        heard = heard.strip()
        intended = intended.strip()
        if not heard or not intended:
            raise ValueError("A correction needs both the heard and the intended text.")
        if source and source not in CORRECTION_SOURCES:
            raise ValueError(f"Unknown correction source: {source!r}.")

        confirmed = Correction(
            heard=heard,
            intended=intended,
            confirmed_at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
            source=source,
        )
        with exclusive_file_lock(self.path):
            kept = [
                item for item in self.load()
                if item.heard.casefold() != heard.casefold()
            ]
            self._write(kept + [confirmed])
        return confirmed

    def remove(self, heard: str) -> bool:
        with exclusive_file_lock(self.path):
            existing = self.load()
            kept = [
                item for item in existing
                if item.heard.casefold() != heard.strip().casefold()
            ]
            if len(kept) == len(existing):
                return False
            self._write(kept)
            return True

    def _write(self, corrections: Sequence[Correction]) -> None:
        write_json_atomically(
            self.path,
            {
                "schema_version": SCHEMA_VERSION,
                "corrections": [
                    {
                        "heard": item.heard,
                        "intended": item.intended,
                        "confirmed_at": item.confirmed_at,
                        **({"source": item.source} if item.source else {}),
                    }
                    for item in corrections
                ],
            },
        )
