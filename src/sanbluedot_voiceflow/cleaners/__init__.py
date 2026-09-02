"""Cleanup providers and the one place that turns a name into one.

R6 keeps provider selection as configuration rather than branching product logic. Every
caller that offers a `--cleaner` flag builds it here, so adding a provider does not mean
finding every `if cleaner ==` in the codebase and hoping none was missed.
"""

from ..contracts import Cleaner
from .gemini import DEFAULT_MODEL as DEFAULT_GEMINI_MODEL
from .gemini import GeminiCleaner
from .literal import LiteralCleaner
from .ollama import OllamaCleaner

__all__ = [
    "CLEANER_NAMES",
    "CLOUD_CLEANER_NAMES",
    "DEFAULT_GEMINI_MODEL",
    "GeminiCleaner",
    "LiteralCleaner",
    "OllamaCleaner",
    "build_cleaner",
]

CLEANER_NAMES = ("literal", "ollama", "gemini")
CLEANER_MODES = ("clean", "translate", "meeting")
# Named separately so a caller can warn, gate, or refuse before anything leaves the
# device, without hard-coding which providers happen to be remote today.
CLOUD_CLEANER_NAMES = ("gemini",)


def build_cleaner(
    name: str,
    *,
    mode: str = "clean",
    ollama_model: str = "qwen3:4b",
    ollama_url: str = "http://127.0.0.1:11434",
    gemini_model: str = DEFAULT_GEMINI_MODEL,
) -> Cleaner:
    if name == "ollama":
        return OllamaCleaner(model=ollama_model, base_url=ollama_url, mode=mode)
    if name == "gemini":
        return GeminiCleaner(model=gemini_model, mode=mode)
    return LiteralCleaner()
