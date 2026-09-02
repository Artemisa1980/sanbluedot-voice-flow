"""Deterministic safety checks for conservative cleanup output."""

import re
import unicodedata

from .errors import CleanupError


_TOKEN = re.compile(
    r"https?://[^\s<>()]+|www\.[^\s<>()]+|"
    r"[\w.+-]+@[\w.-]+\.[a-z]{2,}|\w+(?:['’]\w+)*",
    re.IGNORECASE | re.UNICODE,
)
_PROTECTED_PREFIXES = ("http://", "https://", "www.")
_IGNORABLE_TERMINAL_MARKS = frozenset(".!?")
_CLOSING_MARKS = frozenset("\"'”’)]}»")
# Keep this deliberately narrow. Words such as "like", "este", or "pues" can be
# content in ordinary English or Spanish and are therefore not safe to erase.
_REMOVABLE_FILLERS = frozenset({"um", "uh", "uhm", "erm", "hmm", "mmm"})


def _is_ignorable_presentation_mark(text: str, index: int) -> bool:
    """Allow narrow prose punctuation while protecting executable syntax.

    Internal punctuation can be executable syntax even when it looks grammatical:
    semicolons split shell commands and colons declare code. Commas are the one internal
    mark allowed by the product's punctuation-cleanup requirement, and only directly
    after a token at a whitespace boundary. Periods, questions, and exclamations are
    allowed only at the end of the whole output. Every other symbol remains content.
    """
    if index == 0 or text[index - 1].isspace():
        return False
    if text[index] == ",":
        return index + 1 == len(text) or text[index + 1].isspace()
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


def _tokens(text: str) -> list[tuple[str, bool]]:
    tokens: list[tuple[str, bool]] = []
    normalized = unicodedata.normalize("NFKC", text)
    position = 0
    for match in _TOKEN.finditer(normalized):
        _append_protected_gaps(tokens, normalized, position, match.start())
        token = match.group(0)
        if token.casefold().startswith(_PROTECTED_PREFIXES):
            protected = token.rstrip(".,!?;:)]}")
            tokens.append((protected, False))
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
            tokens.append((token, False))
        else:
            folded = token.casefold()
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
