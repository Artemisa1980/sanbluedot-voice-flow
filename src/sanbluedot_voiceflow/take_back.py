"""Spoken take-backs: the words a speaker uses to withdraw what they just said.

A take-back can only be resolved by deleting words, which the conservative guard refuses
by design. When one of these cues is in a `clean` dictation, the pipeline runs that
dictation as a fix first: the model decides what was withdrawn, and the fix guard still
refuses every word the speaker did not say. When the fix guard refuses, the dictation
gets the ordinary cleanup instead. framework.md R3 draws this.

A cue only decides that the model is asked; it deletes nothing by itself. So the list
leans wide: on the fixed corpus, fix mode over ordinary dictations with no take-back in
them deleted no real word on Apple or on Ollama. What stays out is a bare "no" or "digo"
— "no quiero eso", "te digo que sí" — because nearly every sentence would then pay for a
second model call.
"""

import re
import unicodedata
from collections.abc import Callable

TAKE_BACK_PHRASES = (
    # Spanish
    "borra eso",
    "borrar eso",
    "borralo",
    "borra lo anterior",
    "borrar lo anterior",
    "borra esto",
    "borrar esto",
    "tacha eso",
    "olvida eso",
    "olvidalo",
    "olvida lo anterior",
    "elimina eso",
    "eliminar eso",
    "quita eso",
    "quitar eso",
    "cancela eso",
    "cancelar eso",
    "me equivoque",
    "me confundi",
    "quise decir",
    "mejor dicho",
    "perdon",
    "no no",
    "no mejor",
    "mejor no",
    "no espera",
    "espera no",
    "o sea no",
    "en realidad no",
    "digo no",
    "no digo",
    "corrijo",
    "rectifico",
    # English
    "scratch that",
    "scratch the last",
    "scratch the first",
    "strike that",
    "forget that",
    "forget it",
    "delete that",
    "erase that",
    "remove that",
    "cancel that",
    "never mind",
    "nevermind",
    "take that back",
    "actually no",
    "no actually",
    "no wait",
    "wait no",
    "sorry",
    "i meant",
    "i mean",
    "let me rephrase",
    "start over",
    "do that again",
    "my bad",
    "oops",
)


def _normalized(text: str) -> str:
    """Lowercase, without accents, punctuation turned to spaces, spaces collapsed."""
    decomposed = unicodedata.normalize("NFD", text.casefold())
    unaccented = "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")
    return " ".join(re.sub(r"[^\w]+", " ", unaccented).split())


_PHRASES = tuple(f" {_normalized(phrase)} " for phrase in TAKE_BACK_PHRASES)

EXPLICIT_WIPE_PHRASES = (
    "borra eso",
    "borrar eso",
    "borralo",
    "borra lo anterior",
    "borrar lo anterior",
    "borra esto",
    "borrar esto",
    "tacha eso",
    "olvida eso",
    "olvidalo",
    "olvida lo anterior",
    "elimina eso",
    "eliminar eso",
    "quita eso",
    "quitar eso",
    "cancela eso",
    "cancelar eso",
    "scratch that",
    "scratch the last",
    "scratch the first",
    "strike that",
    "forget that",
    "forget it",
    "delete that",
    "erase that",
    "remove that",
    "cancel that",
    "never mind",
    "nevermind",
    "take that back",
)
_EXPLICIT_WIPE_PHRASES = tuple(f" {_normalized(phrase)} " for phrase in EXPLICIT_WIPE_PHRASES)


def has_take_back(text: str) -> bool:
    """Whether the text contains a spoken take-back cue, as whole words."""
    padded = f" {_normalized(text)} "
    return any(phrase in padded for phrase in _PHRASES)


def has_explicit_wipe_take_back(text: str) -> bool:
    """Whether the text contains an explicit spoken wipe command (e.g. 'borrar eso', 'scratch that')."""
    padded = f" {_normalized(text)} "
    return any(phrase in padded for phrase in _EXPLICIT_WIPE_PHRASES)


# How far a take-back reaches. Withdrawn words sit just before the cue — "a las 4, no,
# mejor no, a las 5" — and a deletion further away is the model erasing the dictation:
# on 2026-09-27 "borra eso" came back as the last sentence alone, 64 words gone.
# Eighteen words covers a full spoken clause before "borrar eso" or "scratch that" while
# still refusing paragraph-wide erasures.
REACH_BEFORE = 18
REACH_AFTER = 3


# Inside a fix, a bare "no" or "digo" can mark where the withdrawn words end — "a Juan,
# digo, a Pedro" — but only when the word before it went too. Counting it on its own
# let a "no" anywhere be deleted and the sentence inverted: "el cliente no aprobó"
# accepted as "el cliente aprobó" (D-39).
_ANCHOR_WORDS = frozenset((
    "no", "digo", "mejor", "perdon", "espera", "borra", "borrar", "elimina", "eliminar",
    "quita", "quitar", "cancela", "cancelar", "wait", "actually", "sorry",
    "scratch", "strike", "delete", "erase", "remove", "cancel",
))


def take_back_spans(
    words: list[str],
    withdrew_before: Callable[[int], bool] = lambda _index: False,
    gone: Callable[[int], bool] = lambda _index: False,
) -> list[tuple[int, int]]:
    """Index ranges, inclusive, of every take-back cue in a list of words.

    Every phrase above is a cue. A bare anchor word is one only when
    `withdrew_before(i)` says the real word just before it was deleted. A bare "no"
    must also join a phrase through words that are all `gone`: "que no" deleted
    together otherwise justified each other, seven words from the real cue, and the
    sentence lost its negation (session-audit-03 F2).
    """
    normalized = [_normalized(word) for word in words]
    phrases: list[tuple[int, int]] = []
    for cue in (_normalized(phrase).split() for phrase in TAKE_BACK_PHRASES):
        size = len(cue)
        for start in range(len(normalized) - size + 1):
            if normalized[start:start + size] == cue:
                phrases.append((start, start + size - 1))

    def joins_a_phrase(index: int) -> bool:
        return any(
            all(gone(between) for between in range(end + 1, index)) if end < index
            else all(gone(between) for between in range(index + 1, start))
            for start, end in phrases
            if not start <= index <= end
        )

    anchors = [
        (index, index) for index, word in enumerate(normalized)
        if word in _ANCHOR_WORDS and withdrew_before(index)
        and (word != "no" or joins_a_phrase(index))
    ]
    return phrases + anchors


def deletable(
    index: int,
    spans: list[tuple[int, int]],
    gone: Callable[[int], bool],
) -> bool:
    """Whether a deleted word belongs to what a take-back withdrew.

    It must lie within reach of a cue, and every word between it and that cue must be
    gone as well. A take-back withdraws one unbroken run of words up to the cue; a word
    kept in between shows the deletion is something else. `gone(i)` is true for a word
    the fix deleted or a filler.
    """
    for start, end in spans:
        if start <= index <= end:
            return True
        if start - REACH_BEFORE <= index < start and all(
            gone(between) for between in range(index + 1, start)
        ):
            return True
        if end < index <= end + REACH_AFTER and all(
            gone(between) for between in range(end + 1, index)
        ):
            return True
    return False


_WORD_RE = re.compile(r"\w+(?:['’]\w+)*", re.UNICODE)


def _resolve_single_take_back(text: str) -> str:
    """Resolve the latest spoken take-back in `text` without crossing sentence boundaries."""
    matches = list(_WORD_RE.finditer(text))
    if not matches:
        return text

    normalized = [_normalized(m.group(0)) for m in matches]
    raw_spans: list[tuple[int, int]] = []
    for cue in (_normalized(phrase).split() for phrase in TAKE_BACK_PHRASES):
        size = len(cue)
        for start in range(len(normalized) - size + 1):
            if normalized[start : start + size] == cue:
                raw_spans.append((start, start + size - 1))

    if not raw_spans:
        return text

    raw_spans.sort()
    # Merge overlapping or adjacent cue phrases separated only by anchor words
    # (e.g. "No, mejor no. Borra eso." -> one combined cue span).
    merged: list[tuple[int, int]] = []
    for start, end in raw_spans:
        while start > 0 and normalized[start - 1] in _ANCHOR_WORDS:
            start -= 1
        if merged and start <= merged[-1][1] + 2 and all(
            normalized[i] in _ANCHOR_WORDS for i in range(merged[-1][1] + 1, start)
        ):
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))

    cue_start, cue_end = merged[-1]
    floor = max(0, cue_start - REACH_BEFORE)
    if cue_start <= floor:
        return text

    # Find the nearest sentence boundary mark before cue_start
    boundary_before_cue: int | None = None
    for idx in range(cue_start - 1, floor - 1, -1):
        gap = text[matches[idx].end() : matches[idx + 1].start()] if idx + 1 < len(matches) else ""
        if any(mark in gap for mark in ".!?;:"):
            boundary_before_cue = idx + 1
            break

    # If all words between the sentence boundary and cue_start are anchor words
    # (e.g. "Meeting a las 4. No, mejor no. Borra eso."), the target sentence is the one before that boundary.
    if boundary_before_cue is not None and all(
        normalized[i] in _ANCHOR_WORDS for i in range(boundary_before_cue, cue_start)
    ):
        sentence_floor = floor
        for idx in range(boundary_before_cue - 2, floor - 1, -1):
            gap = text[matches[idx].end() : matches[idx + 1].start()]
            if any(mark in gap for mark in ".!?;:"):
                sentence_floor = idx + 1
                break
    else:
        sentence_floor = boundary_before_cue if boundary_before_cue is not None else floor

    cue_phrase = " ".join(normalized[cue_start : cue_end + 1])
    is_explicit = any(phrase in cue_phrase for phrase in EXPLICIT_WIPE_PHRASES)

    after_idx = cue_end + 1
    withdraw_start: int | None = None

    # 1. Parallel replacement anchor within current sentence: if the phrase after the cue
    # starts with the same word(s) as the withdrawn phrase before the cue.
    if after_idx < len(matches):
        after_first = normalized[after_idx]
        after_second = normalized[after_idx + 1] if after_idx + 1 < len(matches) else None
        if after_second is not None:
            for idx in range(cue_start - 1, sentence_floor - 1, -1):
                if (
                    idx + 1 < cue_start
                    and normalized[idx] == after_first
                    and normalized[idx + 1] == after_second
                ):
                    withdraw_start = idx
                    break
        if withdraw_start is None:
            for idx in range(cue_start - 1, sentence_floor - 1, -1):
                if normalized[idx] == after_first:
                    withdraw_start = idx
                    break

    # 2. Clause or slip-of-the-tongue wipe within sentence boundaries
    if withdraw_start is None:
        if is_explicit:
            for idx in range(cue_start - 1, sentence_floor, -1):
                gap = text[matches[idx - 1].end() : matches[idx].start()]
                if "," in gap:
                    withdraw_start = idx
                    break
            if withdraw_start is None:
                withdraw_start = sentence_floor
        else:
            withdraw_start = max(sentence_floor, cue_start - 1)

    if withdraw_start is None or withdraw_start >= cue_start:
        return text

    cut_start = matches[withdraw_start].start()
    cut_end = matches[cue_end].end()
    while cut_end < len(text) and text[cut_end] in " \t,.;:!?”’\"'":
        cut_end += 1

    prefix = text[:cut_start]
    suffix = text[cut_end:].lstrip()

    if suffix:
        # Preserve capitalization if the withdrawn segment started a sentence.
        withdrawn_word = matches[withdraw_start].group(0)
        if (
            withdrawn_word[:1].isupper()
            and suffix[:1].islower()
            and (not prefix.strip() or prefix.rstrip()[-1:] in ".!?")
        ):
            suffix = suffix[:1].upper() + suffix[1:]
        result = prefix + suffix
    else:
        result = prefix.rstrip(" ,;:")
        if result and result[-1] not in ".!?":
            result += "."

    return result.strip()


def resolve_take_back_locally(text: str) -> str:
    """Deterministically resolve spoken take-backs within REACH_BEFORE words.

    Used by the local fast-path (Parakeet / fallback) when no LLM is called or when
    an LLM's fix is rejected by the guard. Every result is verified through
    `guard_fix_cleanup` so no word outside `REACH_BEFORE` can ever be erased and no
    word not spoken can ever be introduced.
    """
    if not text or not has_take_back(text):
        return text

    candidate = text
    # Iteratively resolve cues from right to left so each step operates on actual string offsets
    for _ in range(5):
        next_candidate = _resolve_single_take_back(candidate)
        if next_candidate == candidate or not has_take_back(next_candidate):
            candidate = next_candidate
            break
        candidate = next_candidate

    candidate = candidate.strip()
    if not candidate or candidate == text:
        return text

    from .output_guard import guard_fix_cleanup
    from .errors import CleanupError

    try:
        return guard_fix_cleanup(text, candidate)
    except CleanupError:
        return text
