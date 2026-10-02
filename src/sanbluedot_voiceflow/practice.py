"""Pronunciation practice: what the engine heard, against what was read.

R8. A mis-transcription of a known text is acoustic evidence about the speaker. This
module surfaces that evidence and nothing more: it reports the words the engine failed
to recover and keeps the recording so the speaker can listen. It assigns no score and
states no phonetic diagnosis; teaching belongs to the English tutor that reads these
results.
"""

import json
import os
import re
import subprocess
import time
import unicodedata
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from difflib import SequenceMatcher
from pathlib import Path
from typing import Literal

from .errors import DependencyUnavailable
from .memory import (
    exclusive_file_lock,
    quarantine_file,
    read_json_or_quarantine,
    schema_version_is_supported,
    write_json_atomically,
)


SCHEMA_VERSION = 1

DEFAULT_DIRECTORY = Path.home() / "Library/Application Support/sanblue.voiceflow/practice"
DEFAULT_INDEX = DEFAULT_DIRECTORY / "sessions.local.json"

# Enough to separate "six" from "6" in both working languages. A spoken number the
# engine wrote as a numeral is a formatting choice, not a missed word.
_NUMBER_WORDS = {
    "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
    "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
    "eleven": "11", "twelve": "12", "thirteen": "13", "fourteen": "14",
    "fifteen": "15", "sixteen": "16", "seventeen": "17", "eighteen": "18",
    "nineteen": "19", "twenty": "20", "thirty": "30", "forty": "40", "fifty": "50",
    "sixty": "60", "seventy": "70", "eighty": "80", "ninety": "90",
    "hundred": "100", "thousand": "1000", "million": "1000000",
    "oh": "0",
    "cero": "0", "uno": "1", "una": "1", "un": "1", "dos": "2", "tres": "3",
    "cuatro": "4",
    "cinco": "5", "seis": "6", "siete": "7", "ocho": "8", "nueve": "9", "diez": "10",
    "once": "11", "doce": "12", "trece": "13", "catorce": "14", "quince": "15",
    "dieciséis": "16", "dieciseis": "16", "diecisiete": "17",
    "dieciocho": "18", "diecinueve": "19",
    "veinte": "20", "treinta": "30", "cuarenta": "40", "cincuenta": "50",
    "veintiuno": "21", "veintiún": "21", "veintiun": "21", "veintidós": "22",
    "veintidos": "22", "veintitrés": "23", "veintitres": "23",
    "veinticuatro": "24", "veinticinco": "25", "veintiséis": "26",
    "veintiseis": "26", "veintisiete": "27", "veintiocho": "28",
    "veintinueve": "29",
    "sesenta": "60", "setenta": "70", "ochenta": "80", "noventa": "90",
    "cien": "100", "ciento": "100", "doscientos": "200",
    "trescientos": "300", "cuatrocientos": "400", "quinientos": "500",
    "seiscientos": "600", "setecientos": "700", "ochocientos": "800",
    "novecientos": "900", "mil": "1000", "millón": "1000000",
    "millon": "1000000", "millones": "1000000",
}
_NUMBER_CONNECTORS = {"and", "y"}

Kind = Literal["missed", "formatting"]


@dataclass(frozen=True, slots=True)
class Difference:
    read: str
    heard: str
    kind: Kind


# Symbols the engine writes where the speaker said a word. They are stripped by the
# non-word pass below, so the word behind them is restored first: without this,
# "twelve percent" written as "12%" loses the "percent" and is reported as a missed
# word, which tells the speaker they mispronounced something they said correctly.
_SYMBOL_WORDS = {
    "%": " percent ",
    "$": " dollars ",
    "€": " euros ",
    "£": " pounds ",
}

# One canonical token per currency, so the spoken word and the written symbol compare
# equal across languages.
_CURRENCY_WORDS = {
    "dollars": "dollars", "dollar": "dollars", "usd": "dollars",
    "dolares": "dollars", "dolar": "dollars",
    "euros": "euros", "euro": "euros", "eur": "euros",
    "pounds": "pounds", "pound": "pounds", "gbp": "pounds",
}


def _words(text: str) -> list[str]:
    normalized = unicodedata.normalize("NFKC", text).casefold()
    for symbol, word in _SYMBOL_WORDS.items():
        normalized = normalized.replace(symbol, word)
    return re.sub(r"[^\w]+", " ", normalized, flags=re.UNICODE).split()


def _digits(word: str) -> str:
    return _NUMBER_WORDS.get(word, word)


# Acute and diaeresis only. The tilde stays, because año and ano are different words
# and are pronounced differently, while días and dias are the same word written twice.
_WRITTEN_ACCENTS = {"́", "̈"}


def _unaccented(text: str) -> str:
    return "".join(
        character
        for character in unicodedata.normalize("NFD", text)
        if character not in _WRITTEN_ACCENTS
    )


def _summed(words: list[str]) -> str:
    """Render a word sequence with each run of number words summed into one value.

    "forty two" is 42, not 402. Concatenation alone reported that as a missed word,
    which Gate 6 forbids: a spoken number the engine wrote as a numeral is formatting.
    """
    rendered: list[str] = []
    index = 0
    while index < len(words):
        run: list[int] = []
        connectors = 0
        while index < len(words):
            word = words[index]
            if word in _NUMBER_WORDS:
                run.append(int(_NUMBER_WORDS[word]))
                index += 1
                continue
            if (
                word in _NUMBER_CONNECTORS
                and run
                and index + 1 < len(words)
                and words[index + 1] in _NUMBER_WORDS
            ):
                connectors += 1
                index += 1
                continue
            break
        if run:
            should_sum = (
                connectors > 0
                or run[0] in range(20, 100, 10)
                or any(value >= 100 for value in run)
            )
            if not should_sum:
                rendered.append("".join(str(value) for value in run))
                continue
            total = current = 0
            for value in run:
                if value == 100:
                    current = max(current, 1) * 100
                elif value == 1000:
                    total += max(current, 1) * 1000
                    current = 0
                elif value == 1_000_000:
                    total = (total + max(current, 1)) * 1_000_000
                    current = 0
                else:
                    current += value
            rendered.append(str(total + current))
        else:
            rendered.append(words[index])
            index += 1
    return "".join(rendered)


def _canonical_currency(word: str) -> str | None:
    """The canonical name of a currency, or None when the word names no currency."""
    return _CURRENCY_WORDS.get(_unaccented(word))


def _split_currency(words: list[str]) -> tuple[list[str], list[str]]:
    """Separate currency markers from the rest of a span.

    A symbol precedes the amount and the spoken word follows it — `$42,000` against
    "cuarenta y dos mil dólares" — so the marker is compared as a marker rather than in
    place. Everything else keeps its order and is compared normally.
    """
    markers: list[str] = []
    rest: list[str] = []
    for word in words:
        canonical = _canonical_currency(word)
        if canonical is None:
            rest.append(word)
        else:
            markers.append(canonical)
    return sorted(markers), rest


def _percent_collapsed(words: list[str]) -> list[str]:
    """Read "por ciento" as the one word the symbol expands to."""
    collapsed: list[str] = []
    index = 0
    while index < len(words):
        if (
            words[index] == "por"
            and index + 1 < len(words)
            and _unaccented(words[index + 1]) == "ciento"
        ):
            collapsed.append("percent")
            index += 2
            continue
        collapsed.append(words[index])
        index += 1
    return collapsed


def _is_formatting(read: list[str], heard: list[str]) -> bool:
    """True when the two sides differ only in numerals, spacing or written accents.

    Two numeric readings are accepted because both occur. "nine thirty" spoken as a
    time becomes "9 30", which matches by concatenation, while "forty two" becomes
    "42", which matches only once the run is summed. Either match is formatting.

    A missing accent is the engine's spelling choice, not a sound the speaker missed.
    Reporting it as a pronunciation problem would be a false signal, and those arrive
    constantly because whisper.cpp drops Spanish accents often.
    """
    read_collapsed = _percent_collapsed(read)
    heard_collapsed = _percent_collapsed(heard)
    read_markers, read_rest = _split_currency(read_collapsed)
    heard_markers, heard_rest = _split_currency(heard_collapsed)
    if read_markers != heard_markers:
        return False
    # Taking the markers out of their places is only safe when there is one amount to
    # pair them with. With two, the pairing carries meaning that the multiset throws
    # away: "cincuenta dólares y treinta euros" and "treinta dólares y cincuenta euros"
    # hold the same markers and the same sum, and were reported as mere formatting.
    if len(read_markers) > 1:
        read_rest, heard_rest = read_collapsed, heard_collapsed
    concatenated = _unaccented("".join(_digits(w) for w in read_rest)) == _unaccented(
        "".join(_digits(w) for w in heard_rest)
    )
    return concatenated or _unaccented(_summed(read_rest)) == _unaccented(
        _summed(heard_rest)
    )


def compare(reference: str, heard: str) -> list[Difference]:
    """Word-level differences, with engine formatting separated from missed words."""
    read_words, heard_words = _words(reference), _words(heard)
    differences: list[Difference] = []
    matcher = SequenceMatcher(None, read_words, heard_words, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        read_side, heard_side = read_words[i1:i2], heard_words[j1:j2]
        differences.append(
            Difference(
                read=" ".join(read_side),
                heard=" ".join(heard_side),
                kind="formatting" if _is_formatting(read_side, heard_side) else "missed",
            )
        )
    return differences


def recovered_words(reference: str, heard: str) -> int:
    """How many reference words the engine actually returned.

    Zero means the take did not capture the speaker. Reporting that as a pronunciation
    result would be a lie: on near-silence the engine invents text, and with a
    vocabulary prompt loaded it invents terms from the prompt.
    """
    matcher = SequenceMatcher(None, _words(reference), _words(heard), autojunk=False)
    exact = sum(block.size for block in matcher.get_matching_blocks())
    formatted = sum(
        len(_words(item.read))
        for item in compare(reference, heard)
        if item.kind == "formatting"
    )
    return exact + formatted


# No practice take is longer than this. `ffmpeg` enforces it itself, so the microphone
# closes even when the process that started it never gets to stop it.
#
# Found on 2026-09-02: a terminal window was closed while a take was open. The window
# went away, `ffmpeg` did not, and it held the microphone for fourteen minutes writing
# 25.8 MB nothing could list or delete. R7 does not allow a recording to outlive the
# session that asked for it.
MAX_TAKE_SECONDS = 300


def sweep_orphan_takes(
    directory: Path,
    indexed: set[int],
    minimum_age_seconds: float = MAX_TAKE_SECONDS,
    now: float | None = None,
) -> list[Path]:
    """Delete reserved WAV files no session claims, and say which ones went.

    A take is reserved by name before recording starts, so a run that dies between the
    reservation and the index leaves audio of the speaker with no way to reach it. The
    next run removes it rather than leaving it on disk forever.

    A take being recorded right now is also unindexed, and deleting one destroys the
    recording while it is still being made — the speaker then sees "No audio was
    captured. Grant this terminal Microphone access", a diagnosis with nothing to do
    with what happened. Age is what separates the two: `ffmpeg` writes continuously and
    caps itself at `MAX_TAKE_SECONDS`, so a file touched more recently than that may
    still be live and is left alone, while anything older cannot be.
    """
    if not directory.is_dir():
        return []
    moment = time.time() if now is None else now
    removed: list[Path] = []
    for path in sorted(directory.glob("[0-9][0-9][0-9].wav")):
        if not path.stem.isdigit() or int(path.stem) in indexed:
            continue
        try:
            if moment - path.stat().st_mtime < minimum_age_seconds:
                continue
            path.unlink()
        except OSError:
            continue
        removed.append(path)
    return removed


def record(
    destination: Path,
    stop: str = "Press Enter to stop recording…",
    max_seconds: int = MAX_TAKE_SECONDS,
) -> Path:
    """Capture one take from the default input until the speaker stops it."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    command = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "avfoundation", "-i", ":default",
        "-ar", "16000", "-ac", "1", "-sample_fmt", "s16",
        "-t", str(max_seconds),
        str(destination),
    ]
    try:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, text=True)
    except FileNotFoundError as exc:
        raise DependencyUnavailable(
            "ffmpeg is required to record a practice take. Install it with "
            "`brew install ffmpeg`."
        ) from exc

    try:
        input(stop)
    finally:
        try:
            if process.stdin:
                process.stdin.write("q")
                process.stdin.close()
        except (BrokenPipeError, ValueError, OSError):
            process.terminate()  # already gone; the size check below reports why
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired as exc:
            process.kill()
            process.wait()
            raise DependencyUnavailable(
                "ffmpeg did not stop after the recording ended."
            ) from exc

    if not destination.is_file() or destination.stat().st_size <= 44:
        raise DependencyUnavailable(
            "No audio was captured. Grant this terminal Microphone access in "
            "System Settings, then try again."
        )
    return destination


class PracticeStore:
    """Sessions the speaker can list, replay and delete."""

    def __init__(self, directory: Path = DEFAULT_DIRECTORY) -> None:
        self.directory = directory
        self.index = directory / "sessions.local.json"

    def load(self) -> list[dict[str, object]]:
        payload = read_json_or_quarantine(self.index, "The practice session index")
        if payload is None:
            return []
        if not schema_version_is_supported(
            payload,
            self.index,
            "The practice session index",
        ):
            return []
        entries = payload.get("sessions", [])
        if not isinstance(entries, list):
            quarantine_file(
                self.index,
                "The practice session index",
                "the sessions field is not a list",
            )
            return []
        sessions: list[dict[str, object]] = []
        seen_ids: set[int] = set()
        for item in entries:
            if not isinstance(item, dict):
                continue
            if type(item.get("id")) is not int or int(item["id"]) < 1:
                continue
            session_id = int(item["id"])
            if session_id in seen_ids:
                quarantine_file(
                    self.index,
                    "The practice session index",
                    f"duplicate session id: {session_id}",
                )
                return []
            required_strings = ("recorded_at", "reference", "heard", "audio_file")
            if not all(isinstance(item.get(key), str) for key in required_strings):
                continue
            expected_audio = f"{session_id:03d}.wav"
            if item["audio_file"] != expected_audio:
                quarantine_file(
                    self.index,
                    "The practice session index",
                    f"unsafe audio filename for session {session_id}",
                )
                return []
            if not isinstance(item.get("missed", []), list):
                continue
            seen_ids.add(session_id)
            sessions.append(item)
        return sessions

    def sweep_orphans(self) -> list[Path]:
        """Read the index and sweep under one lock.

        Reading the index and then sweeping outside it let a second run compute the
        indexed set before a first run's session was written, and act on a view that
        was already wrong.
        """
        with exclusive_file_lock(self.index):
            indexed = {int(item["id"]) for item in self.load()}
            claimed = self._claimed_ids()
            if claimed is None:
                # The index is still there and still unreadable: moving it aside failed.
                # It may claim every kept take, so nothing is swept (D-54).
                return []
            indexed |= claimed
            indexed |= self._takes_a_quarantined_index_may_claim()
            return sweep_orphan_takes(self.directory, indexed)

    def _claimed_ids(self) -> set[int] | None:
        """Every id the index names, incomplete entries included; None if unreadable."""
        if not self.index.exists():
            return set()
        try:
            payload = json.loads(self.index.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        entries = payload.get("sessions", []) if isinstance(payload, dict) else []
        if not isinstance(entries, list):
            return None
        return {
            item["id"] for item in entries
            if isinstance(item, dict) and type(item.get("id")) is int
        }

    def _takes_a_quarantined_index_may_claim(self) -> set[int]:
        """Takes no older than the last write of an index that was moved aside.

        A quarantined index can no longer say which takes it claimed, and reading it as
        empty deleted every kept recording — in the run that quarantined it and in every
        sweep after (D-54). `os.replace` keeps the file's time, so anything recorded
        before that index was last written may be one of its sessions and is kept; a
        take reserved after it and never indexed is still swept.
        """
        quarantined = list(self.directory.glob(f"{self.index.name}.corrupt-*"))
        if not quarantined:
            return set()
        last_write = max(path.stat().st_mtime for path in quarantined)
        return {
            int(path.stem)
            for path in self.directory.glob("[0-9][0-9][0-9].wav")
            if path.stem.isdigit() and path.stat().st_mtime <= last_write
        }

    def next_audio_path(self) -> Path:
        self.directory.mkdir(parents=True, exist_ok=True)
        with exclusive_file_lock(self.index):
            used = {int(item["id"]) for item in self.load()}
            used.update(
                int(path.stem)
                for path in self.directory.glob("[0-9][0-9][0-9].wav")
                if path.stem.isdigit()
            )
            session_id = max(used, default=0) + 1
            while True:
                destination = self.directory / f"{session_id:03d}.wav"
                try:
                    destination.touch(exist_ok=False)
                    return destination
                except FileExistsError:
                    session_id += 1

    def add(self, reference: str, heard: str, audio: Path) -> dict[str, object]:
        try:
            session_id = int(audio.stem)
        except ValueError as exc:
            raise ValueError(
                "Practice audio must use its reserved numeric filename."
            ) from exc
        if session_id < 1:
            raise ValueError("Practice audio ids must be positive.")
        expected_audio = f"{session_id:03d}.wav"
        if (
            audio.name != expected_audio
            or audio.parent.resolve() != self.directory.resolve()
            or audio.is_symlink()
            or not audio.is_file()
        ):
            raise ValueError(
                "Practice audio must be the reserved WAV inside the practice directory."
            )
        with exclusive_file_lock(self.index):
            sessions = self.load()
            if any(int(item["id"]) == session_id for item in sessions):
                raise ValueError(f"Practice session {session_id} already exists.")
            session = {
                "id": session_id,
                "recorded_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "reference": reference,
                "heard": heard,
                "audio_file": audio.name,
                "missed": [
                    {"read": d.read, "heard": d.heard}
                    for d in compare(reference, heard)
                    if d.kind == "missed"
                ],
            }
            self._write(sessions + [session])
            return session

    def remove(self, session_id: int) -> bool:
        with exclusive_file_lock(self.index):
            sessions = self.load()
            kept = [item for item in sessions if item["id"] != session_id]
            if len(kept) == len(sessions):
                return False
            audio = self.directory / f"{session_id:03d}.wav"
            staged: Path | None = None
            if audio.exists() or audio.is_symlink():
                staged = audio.with_name(
                    f".{audio.name}.{uuid.uuid4().hex}.pending-delete"
                )
                os.replace(audio, staged)
            try:
                self._write(kept)
            except Exception as write_error:
                if staged is not None:
                    try:
                        os.replace(staged, audio)
                    except OSError as restore_error:
                        raise OSError(
                            "The practice index write failed and the audio could not "
                            f"be restored; recover it from {staged}."
                        ) from restore_error
                raise write_error
            if staged is not None:
                try:
                    staged.unlink()
                except OSError as delete_error:
                    try:
                        self._write(sessions)
                        os.replace(staged, audio)
                    except OSError as restore_error:
                        raise OSError(
                            "The practice deletion could not finish cleanly; inspect "
                            f"{staged} and {self.index}."
                        ) from restore_error
                    raise delete_error
            return True

    def _write(self, sessions: list[dict[str, object]]) -> None:
        write_json_atomically(
            self.index, {"schema_version": SCHEMA_VERSION, "sessions": sessions}
        )
