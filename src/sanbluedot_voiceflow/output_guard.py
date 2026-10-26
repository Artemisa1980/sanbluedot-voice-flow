"""Deterministic safety checks for conservative cleanup output."""

import re
import unicodedata

from .errors import CleanupError
from .take_back import deletable, take_back_spans


_TOKEN = re.compile(
    r"https?://[^\s<>()]+|www\.[^\s<>()]+|"
    r"[\w.+-]+@[\w.-]+\.[a-z]{2,}|\w+(?:['’]\w+)*",
    re.IGNORECASE | re.UNICODE,
)
_PROTECTED_PREFIXES = ("http://", "https://", "www.")
# The Spanish written accent, and only that one.
#
# whisper.cpp writes Spanish without it, so a cleaner that puts it back was reported as
# having invented words and every such cleanup was refused — which is most of them, for a
# Spanish speaker. Folding it for the comparison lets `reunion` and `reunión` count as
# one word while the guard keeps judging invention, reordering and deletion.
#
# Deliberately not the other marks: `ñ` and `ü` are letters here, not accents. `ano`
# against `año` and `pinguino` against `pingüino` are different words, and folding them
# would let a cleaner change one into the other unseen.
_ACUTE_ACCENT = "\u0301"
_IGNORABLE_TERMINAL_MARKS = frozenset(".!?")
_CLOSING_MARKS = frozenset("\"'”’)]}»")
_OPENING_MARKS = frozenset("¿¡")
# Keep this deliberately narrow. Words such as "like", "este", or "pues" can be
# content in ordinary English or Spanish and are therefore not safe to erase.
#
# `eh` joined the list on 2026-09-18, by the owner's decision. It was English only until
# then, which cost the speaker every cleanup that removed the one filler she actually
# says: the guard read `eh` as content, refused the whole result and delivered the raw
# transcript. It is an interjection in Spanish, never a content word, which is what
# separates it from `este` and `pues` above.
_REMOVABLE_FILLERS = frozenset({"um", "uh", "uhm", "erm", "hmm", "mmm", "eh"})


def _is_ignorable_presentation_mark(text: str, index: int) -> bool:
    """Allow narrow prose punctuation while protecting executable syntax.

    Internal punctuation can be executable syntax even when it looks grammatical:
    semicolons split shell commands and colons declare code. Commas are the one internal
    mark allowed by the product's punctuation-cleanup requirement, and only directly
    after a token at a whitespace boundary. Periods, questions and exclamations are
    allowed as a run directly after a token, closing quotes included, when whitespace or
    the end of the text follows; `¿` and `¡` only as an opener attached to a word. Every
    other symbol remains content.
    """
    # Spanish opens a question or exclamation with `¿` or `¡`. A cleaner that adds
    # them was refused whole and the speaker got the raw transcript (D-28). Only as an
    # opener: at the start of a word, attached to it.
    if text[index] in _OPENING_MARKS:
        return (
            (index == 0 or text[index - 1].isspace() or text[index - 1] in _OPENING_MARKS)
            and index + 1 < len(text)
            and not text[index + 1].isspace()
        )
    if index == 0 or text[index - 1].isspace():
        return False
    if text[index] == ",":
        return index + 1 == len(text) or text[index + 1].isspace()
    if text[index] in _CLOSING_MARKS:
        prev_index = index - 1
        while prev_index >= 0 and text[prev_index] in _CLOSING_MARKS:
            prev_index -= 1
        if prev_index < 0 or text[prev_index] not in _IGNORABLE_TERMINAL_MARKS:
            return False
        next_index = index + 1
        while next_index < len(text) and text[next_index] in _CLOSING_MARKS:
            next_index += 1
        return next_index == len(text) or text[next_index].isspace()
    if text[index] not in _IGNORABLE_TERMINAL_MARKS:
        return False
    # A run of terminal marks is one piece of presentation, not several tokens.
    # Whisper commonly emits "..." or "?!", and treating every mark but the last as
    # protected content made ordinary punctuation cleanup look like deletion, so the
    # guard rejected it and the speaker silently got the unpunctuated transcript.
    next_index = index + 1
    while next_index < len(text) and (
        text[next_index] in _CLOSING_MARKS
        or text[next_index] in _IGNORABLE_TERMINAL_MARKS
    ):
        next_index += 1
    return next_index == len(text) or text[next_index].isspace()


def _append_protected_gaps(
    tokens: list[tuple[str, bool]], text: str, start: int, end: int
) -> None:
    for index in range(start, end):
        character = text[index]
        if character.isspace() or _is_ignorable_presentation_mark(text, index):
            continue
        tokens.append((character.casefold(), False))


def _fold(token: str) -> str:
    """The form two words are compared in: lowercase, without the written accent.

    The typographic apostrophe is the straight one: `don’t` and `don't` are one word,
    and a cleaner that wrote the curly form was refused whole (D-59).
    """
    decomposed = unicodedata.normalize("NFD", token.casefold().replace("’", "'"))
    return unicodedata.normalize(
        "NFC", "".join(ch for ch in decomposed if ch != _ACUTE_ACCENT)
    )


def _tokens(text: str) -> list[tuple[str, bool]]:
    tokens: list[tuple[str, bool]] = []
    normalized = unicodedata.normalize("NFKC", text)
    position = 0
    for match in _TOKEN.finditer(normalized):
        _append_protected_gaps(tokens, normalized, position, match.start())
        token = match.group(0)
        if token.casefold().startswith(_PROTECTED_PREFIXES):
            protected = token.rstrip(".,!?;:)]}")
            tokens.append((protected.casefold(), False))
            # URL matching intentionally consumes trailing punctuation. Feed that tail
            # back through the symbol guard so `https://safe; rm` cannot hide a command
            # separator inside the URL token.
            _append_protected_gaps(
                tokens,
                normalized,
                match.start() + len(protected),
                match.end(),
            )
        elif "@" in token:
            tokens.append((token.casefold(), False))
        else:
            folded = _fold(token)
            # An all-caps token such as UM may be an acronym, not a spoken filler.
            removable = (
                folded in _REMOVABLE_FILLERS
                and not (len(token) > 1 and token.isupper())
            )
            tokens.append((folded, removable))
        position = match.end()
    _append_protected_gaps(tokens, normalized, position, len(normalized))
    return tokens


def guard_conservative_cleanup(source: str, candidate: str) -> str:
    """Reject lexical invention, reordering, and non-filler deletion.

    A structural guard cannot prove that arbitrary deletion preserves meaning: removing
    a negation can invert a sentence. It therefore permits case, paragraph whitespace,
    narrow prose punctuation, and deletion of a very small unambiguous filler set.
    Unsafe output falls back to the deterministic personalized transcript instead of
    being copied silently.
    """
    if not isinstance(candidate, str):
        raise CleanupError("Cleanup returned a non-text result.")

    source_tokens = _tokens(source)
    candidate_tokens = _tokens(candidate)
    if source_tokens and not candidate_tokens:
        raise CleanupError("Cleanup removed every lexical token.")

    source_index = 0
    for candidate_token, _ in candidate_tokens:
        skipped: list[tuple[str, bool]] = []
        while (
            source_index < len(source_tokens)
            and source_tokens[source_index][0] != candidate_token
        ):
            skipped.append(source_tokens[source_index])
            source_index += 1
        if source_index == len(source_tokens):
            raise CleanupError(
                "Cleanup introduced or reordered lexical content: "
                f"{candidate_token!r}."
            )
        unsafe_deletions = [token for token, removable in skipped if not removable]
        if unsafe_deletions:
            raise CleanupError(
                "Cleanup deleted lexical content that is not an unambiguous filler: "
                f"{unsafe_deletions[0]!r}."
            )
        source_index += 1

    unsafe_tail = [
        token for token, removable in source_tokens[source_index:] if not removable
    ]
    if unsafe_tail:
        raise CleanupError(
            "Cleanup deleted lexical content that is not an unambiguous filler: "
            f"{unsafe_tail[0]!r}."
        )
    return candidate


def guard_fix_cleanup(source: str, candidate: str) -> str:
    """Accept deletion only: every word of the fix must be the speaker's, in order.

    A fix exists to drop what the speaker took back — "no, mejor", "scratch that" — so
    deleting words is its purpose and cannot be refused here. What stays refused is every
    word the speaker never said and every word moved out of its place. That is also what
    catches a model handing back its own example instead of the dictation. The speaker
    asked for the fix on one row, sees the result, and keeps the original.
    """
    if not isinstance(candidate, str):
        raise CleanupError("The fix returned a non-text result.")

    source_tokens = _tokens(source)
    candidate_tokens = _tokens(candidate)
    if source_tokens and not candidate_tokens:
        raise CleanupError("The fix removed every word.")

    # Matched from the end. The corrected version is what the speaker said last, so
    # when a phrase is spoken twice — "el meeting para las 4… borra eso… el meeting a
    # las 6" — the kept words are the later ones and the deleted ones the withdrawn copy.
    kept: set[int] = set()
    source_index = len(source_tokens) - 1
    for candidate_token, _ in reversed(candidate_tokens):
        while source_index >= 0 and source_tokens[source_index][0] != candidate_token:
            source_index -= 1
        if source_index < 0:
            raise CleanupError(
                f"The fix introduced or reordered a word: {candidate_token!r}."
            )
        kept.add(source_index)
        source_index -= 1

    # A take-back withdraws the words just before it, never the dictation. Every word
    # deleted must sit within reach of a cue, in one unbroken run up to it; a filler may
    # go from anywhere.
    def gone(index: int) -> bool:
        return index not in kept or source_tokens[index][1]

    def withdrew_before(index: int) -> bool:
        earlier = index - 1
        while earlier >= 0 and source_tokens[earlier][1]:
            earlier -= 1
        return earlier >= 0 and earlier not in kept

    spans = take_back_spans([token for token, _ in source_tokens], withdrew_before, gone)

    for index, (token, removable) in enumerate(source_tokens):
        if index in kept or removable:
            continue
        if not deletable(index, spans, gone):
            raise CleanupError(
                f"The fix deleted {token!r}, which no take-back withdrew."
            )
    return candidate
