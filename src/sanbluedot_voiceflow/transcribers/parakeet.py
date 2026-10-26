"""Parakeet Ultra on the Neural Engine, reached the way whisper.cpp is.

The model runs through FluidAudio, which is Swift-only, so the engine runs a small helper
and reads what it prints — the same door Apple's cleanup model uses. Parakeet writes its
own punctuation and capitals and takes no vocabulary prompt; confirmed corrections still
apply after it, in the pipeline.
"""

import json
import subprocess
from collections.abc import Callable
from pathlib import Path

from ..contracts import Transcript
from ..errors import DependencyUnavailable, TranscriptionError
from .whisper_cpp import is_effectively_silent, resolve_binary


Runner = Callable[..., subprocess.CompletedProcess[str]]

DEFAULT_BINARY = "voiceflow-parakeet"
DEFAULT_MODEL_DIR = Path("models/fluidaudio/parakeet-ultra")
# The helper's own status for "the model is not on this Mac yet", kept apart from an
# ordinary failure because it calls for a different answer: fetch it once.
MODEL_MISSING_STATUS = 2


class ParakeetTranscriber:
    def __init__(
        self,
        model_dir: Path = DEFAULT_MODEL_DIR,
        binary: str = DEFAULT_BINARY,
        timeout_seconds: float = 120.0,
        runner: Runner = subprocess.run,
    ) -> None:
        self.model_dir = model_dir.expanduser()
        self.binary = binary
        self.timeout_seconds = timeout_seconds
        self._runner = runner

    def transcribe(self, audio_path: Path) -> Transcript:
        audio_path = audio_path.expanduser()
        if not audio_path.is_file():
            raise DependencyUnavailable(f"Audio file not found: {audio_path}")
        if not self.model_dir.is_dir():
            raise DependencyUnavailable(
                f"Parakeet model not found: {self.model_dir}. Fetch it once with "
                f"`voiceflow-parakeet --models {self.model_dir} --download`."
            )
        if is_effectively_silent(audio_path):
            raise TranscriptionError("The recording contains no audible speech.")

        binary_path = resolve_binary(self.binary)
        if binary_path is None:
            raise DependencyUnavailable(f"Parakeet helper not found: {self.binary}")

        command = [
            str(binary_path),
            "--models",
            str(self.model_dir.resolve()),
            str(audio_path.resolve()),
        ]
        try:
            completed = self._runner(
                command,
                capture_output=True,
                text=True,
                errors="replace",
                timeout=self.timeout_seconds,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise TranscriptionError(
                f"Parakeet did not finish within {self.timeout_seconds:.0f} seconds."
            ) from exc
        except (OSError, subprocess.SubprocessError) as exc:
            raise DependencyUnavailable(f"The Parakeet helper could not be run: {exc}") from exc

        detail = (getattr(completed, "stderr", "") or "").strip()[-800:]
        status = getattr(completed, "returncode", 1)
        if status == MODEL_MISSING_STATUS:
            raise DependencyUnavailable(detail or "Parakeet's model is not on this Mac.")
        if status != 0:
            raise TranscriptionError(f"Parakeet failed: {detail or 'unknown error'}")

        # The answer is the JSON line emitted by the helper; walk backwards to skip
        # any trailing diagnostic or runtime shutdown lines (D-199).
        lines = [line for line in (completed.stdout or "").splitlines() if line.strip()]
        data: dict[str, object] | None = None
        for line in reversed(lines):
            try:
                parsed = json.loads(line)
                if isinstance(parsed, dict) and "text" in parsed:
                    data = parsed
                    break
            except (json.JSONDecodeError, TypeError):
                continue
        if data is None or not isinstance(data.get("text"), str):
            raise TranscriptionError("Parakeet returned an invalid answer.")
        text = str(data["text"])
        if not isinstance(text, str) or not text.strip():
            raise TranscriptionError("Parakeet returned an empty transcript.")
        # Parakeet names no language it chose, so the label stays unknown (R2).
        return Transcript(text=text.strip(), language=None)
