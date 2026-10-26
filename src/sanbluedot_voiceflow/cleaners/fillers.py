"""Filler removal with no model, for a speech engine that already punctuates.

Parakeet writes its own punctuation and capitals, which was most of what a cleanup model
added after Whisper. What is left of `clean` on an ordinary dictation is deleting the
guard's own fillers, and that needs no model: it is a list, and the list is the guard's,
so the two cannot drift apart. A model is still asked when a take-back is spoken.
"""

import re

from ..output_guard import _REMOVABLE_FILLERS, guard_conservative_cleanup

# Not next to a hyphen: `uh-huh` and `mm-hmm` are words, and cutting the filler half out
# left `-huh` and `Mm-` (D-76).
_FILLER = re.compile(
    r"(,[ \t]*)?(?<![\w-])("
    + "|".join(re.escape(word) for word in sorted(_REMOVABLE_FILLERS, key=len, reverse=True))
    + r")(?![\w-])[,…]*",
    re.IGNORECASE,
)
# Marks where a removed filler opened a sentence, so only that next word is capitalised.
_OPENED = "\x00"
_SENTENCE_START = re.compile(r"(?:^|[.!?¿¡])[ \t]*$")


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
        opened = _OPENED if _SENTENCE_START.search(text[: match.start()]) else ""
        # ", eh," is one pause, not two: both commas go with the filler. A comma
        # before a filler that has none after it stays where the speaker paused.
        if leading and match.group(0).endswith(","):
            return opened
        return (leading.strip() if leading else "") + opened

    cleaned = _FILLER.sub(drop, text)
    if cleaned == text:
        return text
    cleaned = re.sub(r"[ \t]+([,.;:!?…])", r"\1", cleaned)
    cleaned = re.sub(r",\s*([,.;:!?…])", r"\1", cleaned)
    cleaned = re.sub(
        r"^[\s,.;:…" + _OPENED + r"]+",
        lambda match: _OPENED if _OPENED in match.group(0) else "",
        cleaned,
    )
    cleaned = re.sub(r"([.!?])[ \t]*,[ \t]*", r"\1 ", cleaned)
    cleaned = re.sub(r"([¿¡])[ \t]+", r"\1", cleaned)
    cleaned = re.sub(r"[ \t]{2,}", " ", cleaned).strip()
    # Only the word a removed filler left at a sentence start is capitalised. Every
    # sentence start used to be, which turned `iPhone` into `IPhone` and a web address
    # after a period into one the guard refused (D-92, D-153).
    cleaned = re.sub(
        _OPENED + r"[ \t]*([a-záéíóúñü])",
        lambda match: match.group(1).upper(),
        cleaned,
    )
    cleaned = re.sub(r"[ \t]*" + _OPENED + r"[ \t]*", " ", cleaned).strip()
    cleaned = re.sub(r"([¿¡])[ \t]+", r"\1", cleaned)
    cleaned = re.sub(r"[ \t]{2,}", " ", cleaned)
    try:
        return guard_conservative_cleanup(text, cleaned)
    except Exception:
        return text
