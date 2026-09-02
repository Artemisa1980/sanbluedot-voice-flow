from dataclasses import dataclass
from pathlib import Path
from typing import Protocol


@dataclass(frozen=True, slots=True)
class Transcript:
    text: str
    language: str | None = None


@dataclass(frozen=True, slots=True)
class PipelineResult:
    raw_text: str
    personalized_text: str
    final_text: str
    language: str | None
    cleaner: str
    # Measured stage durations. An interface may only report a latency it was given:
    # these are the wall-clock seconds each stage actually spent, and they are None
    # when the stage did not run, never a placeholder standing in for a measurement.
    transcribe_seconds: float | None = None
    cleanup_seconds: float | None = None


class Transcriber(Protocol):
    def transcribe(self, audio_path: Path) -> Transcript:
        """Convert one local audio file to text."""


class Cleaner(Protocol):
    name: str

    def clean(self, text: str, language_hint: str | None = None) -> str:
        """Transform transcript text without changing its meaning."""
