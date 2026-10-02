"""Cleanup through Apple's on-device model, reached the same way whisper.cpp is.

The model is Swift-only, so it cannot be a Python cleaner directly. It arrives through a
small binary this module runs and reads, which keeps the pipeline, the personalization
and the output guard exactly where `framework.md` draws them. Moving the step into the
application instead would put cleanup in two places and leave the guard applying to one.

Nothing leaves the device: the model runs on this Mac, needs no network and no
credential, so `CLOUD_CLEANER_NAMES` does not list it.
"""

import json
import subprocess
from collections.abc import Callable

from ..errors import CleanupError
from ..transcribers.whisper_cpp import resolve_binary
from .prompt import (
    CONSERVATIVE_SYSTEM_PROMPT,
    FIX_SYSTEM_PROMPT,
    MEETING_NOTES_SYSTEM_PROMPT,
    TRANSLATE_EN_SYSTEM_PROMPT,
)


Runner = Callable[..., subprocess.CompletedProcess[str]]

DEFAULT_BINARY = "voiceflow-apple-cleaner"
DEFAULT_TIMEOUT_SECONDS = 60.0
# The adapter's own status for "this Mac cannot run the model", kept apart from an
# ordinary failure because it calls for a different answer: choose another engine rather
# than try again.
MODEL_UNAVAILABLE_STATUS = 2


class AppleCleaner:
    name = "apple"

    def __init__(
        self,
        binary: str = DEFAULT_BINARY,
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
        mode: str = "clean",
        runner: Runner = subprocess.run,
    ) -> None:
        self.binary = binary
        self.timeout_seconds = timeout_seconds
        self.mode = mode
        self._runner = runner

    def clean(
        self,
        text: str,
        language_hint: str | None = None,
        mode: str | None = None,
    ) -> str:
        # `mode` overrides the constructed mode for this call only. The pipeline uses it
        # to run a `clean` dictation that carries a spoken take-back as a fix.
        active_mode = mode or self.mode
        if not text:
            return text

        if active_mode == "translate":
            system_instruction = TRANSLATE_EN_SYSTEM_PROMPT
        elif active_mode == "meeting":
            system_instruction = MEETING_NOTES_SYSTEM_PROMPT
        elif active_mode == "fix":
            system_instruction = FIX_SYSTEM_PROMPT
        else:
            system_instruction = CONSERVATIVE_SYSTEM_PROMPT

        binary_path = resolve_binary(self.binary)
        if binary_path is None:
            raise CleanupError(
                f"The Apple cleanup binary was not found: {self.binary}. Build it with "
                "`swift build --package-path macos` or choose another engine."
            )

        hint = language_hint or "auto-detected"
        request = json.dumps(
            {
                "instructions": system_instruction,
                "prompt": f"Language hint: {hint}\n\nTranscript:\n{text}",
            },
            ensure_ascii=False,
        )

        try:
            completed = self._runner(
                [str(binary_path)],
                input=request,
                capture_output=True,
                text=True,
                timeout=self.timeout_seconds,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise CleanupError(
                "Apple's on-device model did not finish within "
                f"{self.timeout_seconds:.0f} seconds."
            ) from exc
        except (OSError, subprocess.SubprocessError) as exc:
            raise CleanupError(f"The Apple cleanup binary could not be run: {exc}") from exc

        detail = (getattr(completed, "stderr", "") or "").strip()
        status = getattr(completed, "returncode", 1)
        if status == MODEL_UNAVAILABLE_STATUS:
            raise CleanupError(
                detail or "Apple's on-device model is unavailable on this Mac."
            )
        if status != 0:
            raise CleanupError(detail or "Apple cleanup failed.")

        body = (getattr(completed, "stdout", "") or "").strip()
        try:
            cleaned = json.loads(body)["cleaned_text"]
        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            raise CleanupError("Apple cleanup returned an invalid answer.") from exc
        if not isinstance(cleaned, str) or not cleaned.strip():
            raise CleanupError("Apple cleanup returned empty text.")
        return cleaned.strip()
