"""Cleanup through a local Ollama service, kept for the Windows adapter.

The macOS app stopped offering Ollama on 2026-10-01; Apple's on-device model covers local
cleanup there. Windows has no such model, so this engine keeps the cleaner for it.
"""

import json
import re
from collections.abc import Callable
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from ..errors import CleanupError
from .prompt import (
    CLEANED_TEXT_SCHEMA,
    CONSERVATIVE_SYSTEM_PROMPT,
    FIX_SYSTEM_PROMPT,
    MEETING_NOTES_SYSTEM_PROMPT,
    TRANSLATE_EN_SYSTEM_PROMPT,
    output_token_budget,
)


Opener = Callable[..., Any]

# Ollama is a local engine, so `CLOUD_CLEANER_NAMES` does not list it and nothing on
# screen warns that text leaves the machine. An address elsewhere would send the
# transcript out under that local label, which R7 forbids.
LOCAL_HOSTS = frozenset(("127.0.0.1", "localhost", "::1"))


class OllamaCleaner:
    name = "ollama"

    def __init__(
        self,
        model: str = "qwen3:4b",
        base_url: str = "http://127.0.0.1:11434",
        timeout_seconds: float = 60.0,
        mode: str = "clean",
        opener: Opener = urlopen,
    ) -> None:
        self.model = model
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds
        self.mode = mode
        self._opener = opener

    def clean(
        self,
        text: str,
        language_hint: str | None = None,
        mode: str | None = None,
    ) -> str:
        # `mode` overrides the constructed mode for this call only, as it does for the
        # Apple cleaner: the pipeline runs a take-back in a `clean` dictation as a fix.
        active_mode = mode or self.mode
        if not text:
            return text

        host = urlparse(self.base_url).hostname
        if host not in LOCAL_HOSTS:
            raise CleanupError(
                f"Ollama must run on this machine; {host!r} is not local, so nothing was sent."
            )

        hint = language_hint or "auto-detected"
        if active_mode == "translate":
            system_instruction = TRANSLATE_EN_SYSTEM_PROMPT
        elif active_mode == "meeting":
            system_instruction = MEETING_NOTES_SYSTEM_PROMPT
        elif active_mode == "fix":
            system_instruction = FIX_SYSTEM_PROMPT
        else:
            system_instruction = CONSERVATIVE_SYSTEM_PROMPT
        payload = {
            "model": self.model,
            "stream": False,
            "think": False,
            "keep_alive": "10m",
            "format": CLEANED_TEXT_SCHEMA,
            "messages": [
                {"role": "system", "content": system_instruction},
                {
                    "role": "user",
                    "content": f"Language hint: {hint}\n\nTranscript:\n{text}",
                },
            ],
            "options": {"temperature": 0, "num_predict": output_token_budget(text)},
        }
        request = Request(
            f"{self.base_url}/api/chat",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        try:
            with self._opener(request, timeout=self.timeout_seconds) as response:
                body = response.read().decode("utf-8")
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            raise CleanupError(f"Ollama request failed: {exc}") from exc

        try:
            parsed = json.loads(body)
            content = parsed["message"]["content"]
        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            raise CleanupError("Ollama returned an invalid response.") from exc

        if not isinstance(content, str) or not content.strip():
            raise CleanupError("Ollama returned empty text.")

        cleaned_raw = content.strip()
        if cleaned_raw.startswith("```"):
            cleaned_raw = re.sub(r"^```(?:json)?\s*", "", cleaned_raw)
            cleaned_raw = re.sub(r"\s*```$", "", cleaned_raw).strip()

        try:
            cleaned_text = json.loads(cleaned_raw)["cleaned_text"]
        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            raise CleanupError("Ollama returned invalid cleanup JSON.") from exc
        if not isinstance(cleaned_text, str) or not cleaned_text.strip():
            raise CleanupError("Ollama returned empty cleaned text.")
        return cleaned_text.strip()
