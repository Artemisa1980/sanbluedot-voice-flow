import json
from collections.abc import Callable
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from ..errors import CleanupError
from .prompt import (
    CLEANED_TEXT_SCHEMA,
    CONSERVATIVE_SYSTEM_PROMPT,
    MEETING_NOTES_SYSTEM_PROMPT,
    TRANSFORM_SYSTEM_PROMPT,
    TRANSLATE_EN_SYSTEM_PROMPT,
    output_token_budget,
)


Opener = Callable[..., Any]


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

    def clean(self, text: str, language_hint: str | None = None) -> str:
        if not text:
            return text

        hint = language_hint or "auto-detected"
        if self.mode == "translate":
            system_instruction = TRANSLATE_EN_SYSTEM_PROMPT
        elif self.mode == "meeting":
            system_instruction = MEETING_NOTES_SYSTEM_PROMPT
        elif self.mode == "transform":
            system_instruction = TRANSFORM_SYSTEM_PROMPT
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
            import re
            cleaned_raw = re.sub(r"^```(?:json)?\s*", "", cleaned_raw)
            cleaned_raw = re.sub(r"\s*```$", "", cleaned_raw).strip()

        try:
            cleaned_text = json.loads(cleaned_raw)["cleaned_text"]
        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            raise CleanupError("Ollama returned invalid cleanup JSON.") from exc
        if not isinstance(cleaned_text, str) or not cleaned_text.strip():
            raise CleanupError("Ollama returned empty cleaned text.")
        return cleaned_text.strip()
