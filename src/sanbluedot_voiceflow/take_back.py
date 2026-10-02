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
    "borralo",
    "borra lo anterior",
    "tacha eso",
    "olvida eso",
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
    "corrijo",
    "rectifico",
    # English
    "scratch that",
    "scratch the",
    "strike that",
    "forget that",
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


def has_take_back(text: str) -> bool:
    """Whether the text contains a spoken take-back cue, as whole words."""
    padded = f" {_normalized(text)} "
    return any(phrase in padded for phrase in _PHRASES)


# How far a take-back reaches. Withdrawn words sit just before the cue — "a las 4, no,
# mejor no, a las 5" — and a deletion further away is the model erasing the dictation:
# on 2026-09-27 "borra eso" came back as the last sentence alone, 64 words gone.
REACH_BEFORE = 10
REACH_AFTER = 3


# Inside a fix, a bare "no" or "digo" can mark where the withdrawn words end — "a Juan,
# digo, a Pedro" — but only when the word before it went too. Counting it on its own
# let a "no" anywhere be deleted and the sentence inverted: "el cliente no aprobó"
# accepted as "el cliente aprobó" (D-39).
_ANCHOR_WORDS = frozenset((
    "no", "digo", "mejor", "perdon", "espera", "borra", "wait", "actually", "sorry",
    "scratch", "strike",
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
