"""Cleanup providers and the one place that turns a name into one.

R6 keeps provider selection as configuration rather than branching product logic. Every
caller that offers a `--cleaner` flag builds it here, so adding a provider does not mean
finding every `if cleaner ==` in the codebase and hoping none was missed.
"""

from collections.abc import Sequence

from ..contracts import Cleaner
from .apple import DEFAULT_BINARY as DEFAULT_APPLE_BINARY
from .apple import AppleCleaner
from .gemini import DEFAULT_MODEL as DEFAULT_GEMINI_MODEL
from .gemini import GeminiCleaner
from .literal import LiteralCleaner
from .ollama import OllamaCleaner

__all__ = [
    "AppleCleaner",
    "CLEANER_NAMES",
    "CLOUD_CLEANER_NAMES",
    "DEFAULT_APPLE_BINARY",
    "DEFAULT_GEMINI_MODEL",
    "GeminiCleaner",
    "LiteralCleaner",
    "OllamaCleaner",
    "build_cleaner",
]

# Ollama left the macOS app on 2026-10-01: cleanup time grows with every word a model
# rewrites, and Apple's on-device model and Gemini cover the Mac. The engine keeps it
# for the Windows adapter, which has no on-device model (owner decision, 2026-10-02).
CLEANER_NAMES = ("literal", "apple", "ollama", "gemini")
# Named separately so a caller can warn, gate, or refuse before anything leaves the
# device, without hard-coding which providers happen to be remote today.
CLOUD_CLEANER_NAMES = ("gemini",)


def build_cleaner(
    name: str,
    *,
    mode: str = "clean",
    gemini_model: str = DEFAULT_GEMINI_MODEL,
    apple_binary: str = DEFAULT_APPLE_BINARY,
    apple_examples: Sequence[tuple[str, str]] = (),
    ollama_model: str = "qwen3:4b",
    ollama_url: str = "http://127.0.0.1:11434",
) -> Cleaner:
    if name == "apple":
        return AppleCleaner(
            binary=apple_binary,
            mode=mode,
            few_shot_examples=apple_examples,
        )
    if name == "ollama":
        return OllamaCleaner(model=ollama_model, base_url=ollama_url, mode=mode)
    if name == "gemini":
        return GeminiCleaner(model=gemini_model, mode=mode)
    return LiteralCleaner()
