"""Confirmed local vocabulary and correction memory.

Two layers with different jobs. Vocabulary is preventive: the terms are handed to
the speech engine before it listens, so a rare word is recognized instead of guessed.
Corrections are reparative: a confirmed pair rewrites what the engine still gets
wrong. Neither layer trains a model; both are plain local files the user owns.
"""

import difflib
import json
import os
import re
import sys
import unicodedata
import uuid
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


def _set_private_mode(path: Path, mode: int = 0o600) -> None:
    """Restrict a personal store or export file to the owner (I-25)."""
    try:
        os.chmod(path, mode)
    except OSError:
        pass


def write_text_atomically(path: Path, text: str) -> None:
    """Write through a temporary file in the same directory, flushed to disk, then rename.

    `write_text` truncates first, so an interruption leaves a half-written file. That
    file then fails to parse on every later read, and a corrupted correction store
    blocks dictation entirely. `os.replace` is atomic on the same filesystem, but only
    for what reached the disk: without a flush a power loss right after the rename could
    leave the store empty (D-134). macOS needs `F_FULLFSYNC` for the drive to flush.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        with temporary.open("w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            _flush_to_disk(handle.fileno())
        _set_private_mode(temporary, 0o600)
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            _flush_to_disk(directory)
        finally:
            os.close(directory)
    finally:
        temporary.unlink(missing_ok=True)


def _flush_to_disk(descriptor: int) -> None:
    try:
        import fcntl

        fcntl.fcntl(descriptor, fcntl.F_FULLFSYNC)
    except (ImportError, AttributeError, OSError):
        os.fsync(descriptor)


def write_json_atomically(path: Path, payload: object) -> None:
    """The JSON stores' writer: one atomic, flushed write."""
    write_text_atomically(path, json.dumps(payload, ensure_ascii=False, indent=2) + "\n")


@contextmanager
def exclusive_file_lock(path: Path) -> Iterator[None]:
    """Serialize one store's read-modify-write cycle across local processes."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_name(f".{path.name}.lock")
    with lock_path.open("a+b") as handle:
        _set_private_mode(lock_path, 0o600)
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


def _identity(path: Path) -> tuple[int, int, int] | None:
    try:
        status = path.stat()
    except OSError:
        return None
    return (status.st_ino, status.st_mtime_ns, status.st_size)


def quarantine_file(
    path: Path,
    kind: str,
    error: object,
    read_identity: tuple[int, int, int] | None = None,
) -> None:
    """Preserve one unusable personal file under a dated name and report it.

    `read_identity` is the file as it was when the read failed. If another process has
    rewritten it since, the bad copy is already gone and the good one is left in place:
    a slow reader used to move aside a store another process had just written (D-135).
    The store lock is not taken here, because callers already hold it and `flock`
    blocks against itself.
    """
    if read_identity is not None and _identity(path) != read_identity:
        print(
            f"{kind} could not be read ({error}), but it changed since; the new copy "
            "is kept and this run continues without the old one.",
            file=sys.stderr,
        )
        return
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    quarantine = path.with_name(f"{path.name}.corrupt-{stamp}")
    try:
        os.replace(path, quarantine)
    except OSError as move_error:
        # The move failed, so the file is where it was; saying "moved to" its own
        # name was a report of something that did not happen (D-154).
        print(
            f"{kind} could not be read ({error}), and it could not be moved aside "
            f"({move_error}); it was left in place and this run continues without it.",
            file=sys.stderr,
        )
        return
    print(
        f"{kind} could not be read ({error}). It was moved to {quarantine.name} and "
        "this run continues without it.",
        file=sys.stderr,
    )


def preserve_skipped(path: Path, kind: str, skipped: int) -> None:
    """Keep one copy of a store some of whose entries could not be read.

    Unreadable entries were skipped in silence and then vanished at the next write
    (D-97, D-30). The copy is named by the file's content, so it is written once per
    version of the file rather than on every read, and the speaker is told once.
    """
    if skipped <= 0:
        return
    import hashlib

    try:
        data = path.read_bytes()
    except OSError:
        return
    copy = path.with_name(f"{path.name}.skipped-{hashlib.sha1(data).hexdigest()[:10]}")
    if copy.exists():
        return
    try:
        copy.write_bytes(data)
    except OSError:
        return
    print(
        f"{kind} has {skipped} unreadable entr{'y' if skipped == 1 else 'ies'}; they are "
        f"skipped, and the file as it was is kept as {copy.name}.",
        file=sys.stderr,
    )


def read_json_or_quarantine(path: Path, kind: str) -> dict[str, object] | None:
    """Return parsed JSON, or move an unreadable file aside and return None.

    Personal memory must never be able to stop the speaker from dictating. A damaged
    file is preserved under a dated name rather than deleted, and the loss is reported.
    """
    if not path.is_file():
        return None
    identity = _identity(path)
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("the top-level JSON value is not an object")
        return payload
    except (json.JSONDecodeError, UnicodeDecodeError, OSError, ValueError) as exc:
        quarantine_file(path, kind, exc, read_identity=identity)
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
    # Every line break `splitlines` honours, not only `\n`: a `\r` or `\x0b` stored one
    # term as two (D-155). A leading `#` is a comment to the reader, so the term was
    # reported added and never loaded (D-89).
    if not term or len(term.splitlines()) != 1:
        raise ValueError("A vocabulary term is one line of text.")
    if term.startswith("#"):
        raise ValueError("A vocabulary term cannot start with #, which marks a comment.")
    with exclusive_file_lock(path):
        existing = load_vocabulary(path)
        if term.casefold() in {item.casefold() for item in existing}:
            return False
        try:
            lines = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
        except (UnicodeDecodeError, OSError) as exc:
            quarantine_file(path, "The vocabulary store", exc)
            lines = []
        _write_lines_atomically(path, lines + [term])
    return True


def remove_vocabulary_term(term: str, path: Path = DEFAULT_VOCABULARY) -> bool:
    """Remove one term, keeping every other line and comment in its place."""
    wanted = term.strip().casefold()
    if not wanted or not path.is_file():
        return False
    with exclusive_file_lock(path):
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (UnicodeDecodeError, OSError) as exc:
            quarantine_file(path, "The vocabulary store", exc)
            return False
        kept = [line for line in lines if line.strip().casefold() != wanted]
        if len(kept) == len(lines):
            return False
        _write_lines_atomically(path, kept)
    return True


def _write_lines_atomically(path: Path, lines: Sequence[str]) -> None:
    write_text_atomically(path, "".join(f"{line}\n" for line in lines))


def prompt_terms(terms: Sequence[str], char_budget: int = PROMPT_CHAR_BUDGET) -> list[str]:
    """The leading terms the prompt carries. Counted here, not by splitting the prompt
    on ", ", which read a term containing ", " as two (D-96)."""
    selected: list[str] = []
    used = 0
    for term in terms:
        cost = len(term) + (2 if selected else 0)
        if used + cost > char_budget:
            break
        selected.append(term)
        used += cost
    return selected


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
    measured on the fixed corpus with punctuation first — `docs/proposals/phase-5-proposal.md`, 8.
    """
    return ", ".join(prompt_terms(terms, char_budget))


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

    # The window's last ten dictations, written by the app. They lived in user defaults
    # and never reached this file (D-11); an unreadable copy exports as empty.
    history_path = directory / "history.local.json"
    try:
        history = json.loads(history_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        history = []
    if not isinstance(history, list):
        history = []

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
            "dictation_history": history,
        },
    )
    counts = {
        "vocabulary": len(terms),
        "corrections": len(corrections),
        "practice_sessions": len(practice_sessions),
        "snippets": len(snippets),
        "distillation_pairs": len(distillation_pairs),
        "dictation_history": len(history),
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
    # Words joined by any whitespace, so a double space or a tab still matches (D-161).
    escaped = r"\s+".join(re.escape(word) for word in heard.split())
    prefix = r"\b" if heard[:1].isalnum() or heard[:1] == "_" else ""
    suffix = r"\b" if heard[-1:].isalnum() or heard[-1:] == "_" else ""
    return re.compile(f"{prefix}{escaped}{suffix}", re.IGNORECASE)


def _match_case(matched: str, replacement: str) -> str:
    # A capital after the first letter (`iPhone`, `eBay`) is a spelling the speaker
    # confirmed, not a case to adjust; a sentence start used to make it `IPhone`.
    # `CorrectionApplication.matchingCase` in `Words.swift` holds the same rule.
    if any(character.isupper() for character in replacement[1:]):
        return replacement
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
    by_key = {" ".join(item.heard.split()).casefold(): item.intended for item in ordered}
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


def _fold_vocab_token(token: str) -> str:
    decomposed = unicodedata.normalize("NFD", token.casefold())
    return "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")


def _phonetic_vocab_token(token: str) -> str:
    """Normalize bilingual Spanish/English phonetic equivalents for fuzzy term alignment."""
    folded = _fold_vocab_token(token)
    for src, dst in (("qu", "k"), ("ck", "k"), ("ee", "e"), ("oo", "u"), ("ph", "f"), ("ll", "y")):
        folded = folded.replace(src, dst)
    return folded


_URL_PATH_EMAIL_RE = re.compile(
    r"(https?://[^\s]+|/[a-zA-Z0-9_\.\-]+/[^\s]*|[a-zA-Z0-9_\.\-]+@[a-zA-Z0-9_\.\-]+)",
    re.UNICODE,
)
_VERB_ENDINGS = ("ar", "er", "ir", "ando", "endo", "ado", "ido", "ing", "ed")


def align_vocabulary(text: str, vocabulary: Sequence[str]) -> str:
    """Align spoken tokens to canonical terms from vocabulary.local.txt.

    Parakeet Ultra accepts no initial prompt before recognition. Post-transcription
    vocabulary alignment gives Parakeet (and Whisper) the speaker's canonical casing,
    accents, and high-precision phonetic alignment for distinctive terms (>= 6 chars).
    URLs, file paths, email addresses, plurals, and grammatical verb inflections are
    strictly protected from phonetic substitution.
    """
    if not text or not vocabulary:
        return text

    clean_terms = [t.strip() for t in vocabulary if t and t.strip()]
    if not clean_terms:
        return text

    # Split by URLs/paths/emails to avoid mutating technical identifiers
    segments = _URL_PATH_EMAIL_RE.split(text)

    # 1. Exact case-folded / phrase-level canonical casing & orthography alignment
    synthetic_corrections = [
        Correction(heard=term, intended=term, confirmed_at="", source="")
        for term in clean_terms
        if any(c.isupper() for c in term) or not term.isascii()
    ]

    # 2. High-precision single-word phonetic/fuzzy alignment for distinctive terms (>= 6 chars)
    single_terms = [
        (term, _fold_vocab_token(term), _phonetic_vocab_token(term))
        for term in clean_terms
        if " " not in term and len(term) >= 6
    ]

    exact_folded = {folded for _, folded, _ in single_terms}
    word_re = re.compile(r"\b\w+\b", re.UNICODE)

    def replace_token(match: re.Match[str]) -> str:
        word = match.group(0)
        if len(word) < 6:
            return word
        folded_word = _fold_vocab_token(word)
        if folded_word in exact_folded:
            for canonical, folded_term, _ in single_terms:
                if folded_term == folded_word:
                    return _match_case(word, canonical)
            return word

        phonetic_word = _phonetic_vocab_token(word)
        best_canonical: str | None = None
        best_ratio = 0.90
        for canonical, folded_term, phonetic_term in single_terms:
            if phonetic_word[:1] != phonetic_term[:1]:
                continue
            if abs(len(phonetic_word) - len(phonetic_term)) > 1:
                continue
            # Plural protection
            if folded_word.endswith("s") != folded_term.endswith("s"):
                continue
            # Morphological inflection protection (e.g. Spanish verb "terminar" vs "terminal")
            if folded_word.endswith(_VERB_ENDINGS) and not folded_term.endswith(_VERB_ENDINGS):
                continue

            ratio = max(
                difflib.SequenceMatcher(None, folded_word, folded_term).ratio(),
                difflib.SequenceMatcher(None, phonetic_word, phonetic_term).ratio(),
            )
            if ratio >= best_ratio:
                best_ratio = ratio
                best_canonical = canonical
        if best_canonical is not None:
            return _match_case(word, best_canonical)
        return word

    processed_segments: list[str] = []
    for i, seg in enumerate(segments):
        if i % 2 == 1:
            # Matched URL, path or email token -> deliver unchanged
            processed_segments.append(seg)
        else:
            aligned = apply_corrections(seg, synthetic_corrections) if synthetic_corrections else seg
            if single_terms:
                aligned = word_re.sub(replace_token, aligned)
            processed_segments.append(aligned)

    return "".join(processed_segments)


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
        skipped = 0
        for entry in entries:
            # An entry missing either side would rewrite text unpredictably; skip it.
            if not isinstance(entry, dict):
                skipped += 1
                continue
            heard, intended = entry.get("heard"), entry.get("intended")
            if not isinstance(heard, str) or not isinstance(intended, str):
                skipped += 1
                continue
            if not heard.strip() or not intended.strip():
                skipped += 1
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
        preserve_skipped(self.path, "The correction store", skipped)
        return corrections

    def add(self, heard: str, intended: str, source: str = "") -> Correction:
        """Store one pair the user confirmed. Re-adding a pair replaces it."""
        heard = " ".join(heard.split())
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
