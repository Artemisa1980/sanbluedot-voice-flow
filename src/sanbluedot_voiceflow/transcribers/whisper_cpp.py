import math
import os
import re
import shutil
import subprocess
import tempfile
import wave
from array import array
from collections.abc import Callable
from pathlib import Path

from ..contracts import Transcript
from ..errors import DependencyUnavailable, TranscriptionError


Runner = Callable[..., subprocess.CompletedProcess[str]]


# Measured recordings sit around 0.024 RMS, the quietest at 0.020. This floor is far
# below any real take, so it rejects silence without rejecting a soft speaker.
SILENCE_RMS = 0.003


def is_effectively_silent(audio_path: Path, floor: float = SILENCE_RMS) -> bool:
    """True when a 16-bit PCM WAV carries no speech worth transcribing.

    A near-silent take makes whisper.cpp invent text, and with an initial prompt loaded
    it invents terms from that prompt. Without this guard, holding the shortcut by
    accident copies fabricated vocabulary to the clipboard. Unreadable or unexpected
    audio fails open, because a format this cannot parse is not evidence of silence.
    """
    try:
        with wave.open(str(audio_path)) as source:
            if source.getsampwidth() != 2:
                return False
            frames = source.readframes(source.getnframes())
    except (wave.Error, OSError, EOFError):
        return False

    samples = array("h", frames[: len(frames) - (len(frames) % 2)])
    if not samples:
        return True
    mean_square = sum(sample * sample for sample in samples) / len(samples)
    return math.sqrt(mean_square) / 32768 < floor


# whisper.cpp announces its automatic choice on stderr as
# `whisper_full_with_state: auto-detected language: es (p = 0.98)`. Verified against
# the local whisper-cli build: the line never reaches stdout and never reaches the
# generated transcript file, so the label is lost unless this output is read.
AUTO_LANGUAGE = re.compile(r"auto-detected language:\s*([A-Za-z]{2,3})")


def detected_language(completed: object) -> str | None:
    """Recover the language whisper.cpp selected in automatic mode.

    An absent, unreadable or unparsable line returns None. The detected label is
    engine evidence; when the engine did not report one, it stays unknown rather
    than being guessed from the transcript.
    """
    for stream in (
        getattr(completed, "stderr", None),
        getattr(completed, "stdout", None),
    ):
        if not isinstance(stream, str):
            continue
        found = AUTO_LANGUAGE.findall(stream)
        if found:
            return found[-1].lower()
    return None


def is_executable_file(path: Path) -> bool:
    """Whether this path is a file the system can actually execute.

    `os.access(path, os.X_OK)` answers true for every existing file on Windows, so it
    decides nothing there and would admit a text file named after the binary. Windows
    decides by extension instead, and `PATHEXT` is the list it decides from.
    """
    if not path.is_file():
        return False
    if os.name != "nt":
        return os.access(path, os.X_OK)
    extensions = [
        extension.strip().lower()
        for extension in os.environ.get("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(os.pathsep)
        if extension.strip()
    ]
    return path.suffix.lower() in extensions


def resolve_binary(value: str) -> Path | None:
    candidate = Path(value).expanduser()
    if candidate.parent != Path("."):
        return candidate.resolve() if is_executable_file(candidate) else None
    resolved = shutil.which(value)
    return Path(resolved) if resolved else None


class WhisperCppTranscriber:
    def __init__(
        self,
        model_path: Path,
        binary: str = "whisper-cli",
        language: str = "auto",
        timeout_seconds: float = 120.0,
        initial_prompt: str = "",
        threads: int | None = None,
        beam_size: int | None = None,
        runner: Runner = subprocess.run,
    ) -> None:
        self.model_path = model_path.expanduser()
        self.binary = binary
        self.language = language
        self.timeout_seconds = timeout_seconds
        self.initial_prompt = initial_prompt
        self.threads = threads
        self.beam_size = beam_size
        self._runner = runner

    def transcribe(self, audio_path: Path) -> Transcript:
        audio_path = audio_path.expanduser()
        if not audio_path.is_file():
            raise DependencyUnavailable(f"Audio file not found: {audio_path}")
        if not self.model_path.is_file():
            raise DependencyUnavailable(f"Whisper model not found: {self.model_path}")
        # Reading one byte is what proves the file readable. `os.access(path, os.R_OK)`
        # answers true on Windows for a file whose owner is the caller whatever its
        # permissions say, so it lets an unreadable model through to the subprocess.
        try:
            with self.model_path.open("rb") as handle:
                handle.read(1)
        except OSError as error:
            raise DependencyUnavailable(
                f"Whisper model is not readable: {self.model_path}"
            ) from error
        if is_effectively_silent(audio_path):
            raise TranscriptionError("The recording contains no audible speech.")

        binary_path = resolve_binary(self.binary)
        if binary_path is None:
            raise DependencyUnavailable(f"Whisper binary not found: {self.binary}")

        with tempfile.TemporaryDirectory(prefix="sanbluedot-voiceflow-") as temp_dir:
            output_base = Path(temp_dir) / "transcript"
            command = [
                str(binary_path),
                "-m",
                str(self.model_path.resolve()),
                "-f",
                str(audio_path.resolve()),
                "-l",
                self.language,
                "-otxt",
                "-of",
                str(output_base),
            ]
            if self.initial_prompt:
                # Bias recognition toward the confirmed vocabulary before decoding.
                command += ["--prompt", self.initial_prompt]
            if self.threads is not None:
                command += ["-t", str(self.threads)]
            if self.beam_size is not None:
                command += ["-bs", str(self.beam_size)]

            try:
                completed = self._runner(
                    command,
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=self.timeout_seconds,
                    cwd=str(binary_path.parent),
                )
            except FileNotFoundError as exc:
                raise DependencyUnavailable(f"Whisper binary not found: {binary_path}") from exc
            except subprocess.TimeoutExpired as exc:
                raise TranscriptionError(
                    "whisper.cpp did not finish within "
                    f"{self.timeout_seconds:.0f} seconds."
                ) from exc
            except subprocess.CalledProcessError as exc:
                detail = (exc.stderr or exc.stdout or "unknown error").strip()[-800:]
                raise TranscriptionError(f"whisper.cpp failed: {detail}") from exc

            output_file = Path(f"{output_base}.txt")
            if not output_file.is_file():
                raise TranscriptionError("whisper.cpp did not create a text transcript.")

            try:
                text = output_file.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError) as exc:
                raise TranscriptionError(
                    f"whisper.cpp transcript could not be read: {exc}"
                ) from exc
            if not text.strip():
                raise TranscriptionError("whisper.cpp returned an empty transcript.")
            # whisper.cpp writes one newline as the text-file record delimiter. It is
            # transport framing, not transcript content; preserve every other byte of
            # decoded text, including leading and trailing spaces or extra newlines.
            if text.endswith("\r\n"):
                text = text[:-2]
            elif text.endswith("\n"):
                text = text[:-1]

        language = (
            detected_language(completed) if self.language == "auto" else self.language
        )
        return Transcript(text=text, language=language)
