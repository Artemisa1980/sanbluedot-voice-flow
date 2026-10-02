"""Filler removal with no model, for a speech engine that already punctuates.

Parakeet writes its own punctuation and capitals, which was most of what a cleanup model
added after Whisper. What is left of `clean` on an ordinary dictation is deleting the
guard's own fillers, and that needs no model: it is a list, and the list is the guard's,
so the two cannot drift apart. A model is still asked when a take-back is spoken.
"""

import re

from ..output_guard import _REMOVABLE_FILLERS, guard_conservative_cleanup

_FILLER = re.compile(
    r"(,[ \t]*)?(?<!\w)("
    + "|".join(re.escape(word) for word in sorted(_REMOVABLE_FILLERS, key=len, reverse=True))
    + r")(?!\w)[,…]*",
    re.IGNORECASE,
)


def remove_fillers(text: str) -> str:
    """Delete the fillers and the commas hanging on them; change nothing else.

    An all-caps token such as UM may be an acronym, so it stays, as the guard reads it.
    A sentence that opened on a filler keeps its capital on the next word. The result is
    checked by the same guard every cleanup faces, and the text is returned unchanged
    if it would not pass.
    """

    def drop(match: re.Match[str]) -> str:
        leading, word = match.group(1), match.group(2)
        if len(word) > 1 and word.isupper():
            return match.group(0)
        # ", eh," is one pause, not two: both commas go with the filler. A comma
        # before a filler that has none after it stays where the speaker paused.
        if leading and match.group(0).endswith(","):
            return ""
        return leading.strip() if leading else ""

    cleaned = _FILLER.sub(drop, text)
    if cleaned == text:
        return text
    cleaned = re.sub(r"[ \t]+([,.;:!?…])", r"\1", cleaned)
    cleaned = re.sub(r",\s*([,.;:!?…])", r"\1", cleaned)
    cleaned = re.sub(r"^[\s,.;:…]+", "", cleaned)
    cleaned = re.sub(r"([.!?])[ \t]*,[ \t]*", r"\1 ", cleaned)
    cleaned = re.sub(r"[ \t]{2,}", " ", cleaned).strip()
    cleaned = re.sub(
        r"(^|[.!?][ \t]+)([a-záéíóúñü])",
        lambda match: match.group(1) + match.group(2).upper(),
        cleaned,
    )
    try:
        return guard_conservative_cleanup(text, cleaned)
    except Exception:
        return text
