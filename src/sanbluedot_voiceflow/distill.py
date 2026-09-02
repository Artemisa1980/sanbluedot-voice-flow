import json
import re
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .cleaners.prompt import (
    CONSERVATIVE_SYSTEM_PROMPT,
    MEETING_NOTES_SYSTEM_PROMPT,
    TRANSLATE_EN_SYSTEM_PROMPT,
)
from .errors import VoiceFlowError
from .memory import DEFAULT_DIRECTORY, exclusive_file_lock

DEFAULT_DISTILL_STORE = DEFAULT_DIRECTORY / "distill_pairs.local.jsonl"
DEFAULT_BASE_MODEL = "qwen2.5:3b"
DEFAULT_DISTILLED_MODEL_NAME = "sanblue-voiceflow"


@dataclass(frozen=True)
class DistillationPair:
    raw_text: str
    cleaned_text: str
    mode: str
    cleaner: str
    model: str | None = None
    timestamp: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {k: v for k, v in asdict(self).items() if v is not None}

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "DistillationPair":
        if not isinstance(data, dict):
            raise ValueError("DistillationPair payload must be a dictionary.")
        raw = data.get("raw_text")
        cleaned = data.get("cleaned_text")
        if not isinstance(raw, str) or not isinstance(cleaned, str) or not raw.strip() or not cleaned.strip():
            raise ValueError("DistillationPair raw_text and cleaned_text must be non-empty strings.")
        return cls(
            raw_text=raw.strip(),
            cleaned_text=cleaned.strip(),
            mode=str(data.get("mode", "clean")),
            cleaner=str(data.get("cleaner", "gemini")),
            model=data.get("model") if isinstance(data.get("model"), str) else None,
            timestamp=data.get("timestamp") if isinstance(data.get("timestamp"), str) else None,
        )



class DistillationStore:
    """Stores and retrieves high-quality raw -> cleaned pairs for local distillation."""

    def __init__(self, path: Path = DEFAULT_DISTILL_STORE) -> None:
        self.path = path

    def record(
        self,
        raw_text: str,
        cleaned_text: str,
        mode: str = "clean",
        cleaner: str = "gemini",
        model: str | None = None,
    ) -> DistillationPair:
        raw = raw_text.strip()
        cleaned = cleaned_text.strip()
        if not raw or not cleaned:
            raise VoiceFlowError("Cannot record empty distillation pair.")

        pair = DistillationPair(
            raw_text=raw,
            cleaned_text=cleaned,
            mode=mode,
            cleaner=cleaner,
            model=model,
            timestamp=datetime.now(timezone.utc).isoformat(),
        )

        self.path.parent.mkdir(parents=True, exist_ok=True)
        with exclusive_file_lock(self.path):
            with self.path.open("a", encoding="utf-8") as f:
                f.write(json.dumps(pair.to_dict(), ensure_ascii=False) + "\n")
        return pair

    def load_all(self, mode: str | None = None) -> list[DistillationPair]:
        with exclusive_file_lock(self.path):
            return self._read_pairs(mode)

    def _read_pairs(self, mode: str | None = None) -> list[DistillationPair]:
        """Read the store without taking the lock.

        `flock` is held per open file description, so a locked method that calls
        another locked method blocks against itself forever. Every caller that already
        holds the lock reads through here instead.
        """
        if not self.path.exists():
            return []

        pairs: list[DistillationPair] = []
        with self.path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    pair = DistillationPair.from_dict(data)
                    if mode is None or pair.mode == mode:
                        pairs.append(pair)
                except (json.JSONDecodeError, KeyError, TypeError, ValueError):
                    continue
        return pairs

    def count_by_mode(self) -> dict[str, int]:
        pairs = self.load_all()
        counts: dict[str, int] = {}
        for p in pairs:
            counts[p.mode] = counts.get(p.mode, 0) + 1
        return counts

    def clear(self) -> int:
        """Delete every stored pair and the store file, and say how many were held.

        R7 requires local user data to be deletable. These pairs are the speaker's own
        sentences, so removal takes the file with it rather than leaving an empty one
        that still records that dictation happened.
        """
        with exclusive_file_lock(self.path):
            removed = len(self._read_pairs())
            self.path.unlink(missing_ok=True)
        return removed

    def export_jsonl(self, dest: Path, mode: str | None = None) -> int:
        """Copy the pairs to another file.

        Exporting onto the store itself is refused. The destination is opened for
        writing, which truncates it, so a mode-filtered export onto the store would
        silently drop every pair of the other modes — three pairs became one in the
        audit that found this. Deleting pairs is what `clear` is for, and it asks.
        """
        if dest.resolve() == self.path.resolve():
            raise VoiceFlowError(
                f"{dest} is the distillation store itself. Export to another path; "
                "writing over the store would delete every pair outside --mode."
            )
        pairs = self.load_all(mode=mode)
        dest.parent.mkdir(parents=True, exist_ok=True)
        with exclusive_file_lock(dest):
            with dest.open("w", encoding="utf-8") as f:
                for p in pairs:
                    f.write(json.dumps(p.to_dict(), ensure_ascii=False) + "\n")
        return len(pairs)


def _sanitize_modelfile_text(text: str) -> str:
    """Escape triple quotes and normalize trailing backslashes for Modelfile message blocks."""
    sanitized = text.replace('"""', r'\"\"\"').strip()
    if sanitized.endswith('\\') and not sanitized.endswith(r'\\'):
        sanitized += ' '
    return sanitized


def build_modelfile(
    base_model: str = DEFAULT_BASE_MODEL,
    mode: str = "all",
    pairs: Sequence[DistillationPair] = (),
    max_examples_per_mode: int = 4,
) -> str:
    """Generate an Ollama Modelfile with tailored system prompts and few-shot pairs."""
    clean_base = base_model.strip()
    if not re.match(r"^[a-zA-Z0-9_\-./:]+$", clean_base):
        raise VoiceFlowError(f"Invalid base model identifier: {base_model!r}")

    lines: list[str] = [
        f"FROM {clean_base}",
        "",
        "# Runtime parameters for deterministic, high-accuracy dictation",
        "PARAMETER temperature 0",
        "PARAMETER top_p 0.9",
        "PARAMETER stop \"<|im_end|>\"",
        "PARAMETER stop \"<|endoftext|>\"",
        "PARAMETER stop \"<|eot_id|>\"",
        "",
    ]

    if mode == "translate":
        system_prompt = TRANSLATE_EN_SYSTEM_PROMPT
    elif mode == "meeting":
        system_prompt = MEETING_NOTES_SYSTEM_PROMPT
    elif mode == "clean":
        system_prompt = CONSERVATIVE_SYSTEM_PROMPT
    else:
        # Multi-mode universal prompt
        system_prompt = (
            "You are sanblue VoiceFlow, an expert assistant for real-time speech cleanup, "
            "translation into professional US English, and Markdown meeting formatting. "
            "Always follow the requested mode and return valid JSON with key 'cleaned_text'."
        )

    lines.append(f'SYSTEM """{_sanitize_modelfile_text(system_prompt)}"""\n')

    # Add curated few-shot examples from distillation pairs
    filtered_pairs = [p for p in pairs if mode == "all" or p.mode == mode]
    by_mode: dict[str, list[DistillationPair]] = {}
    for p in filtered_pairs:
        by_mode.setdefault(p.mode, []).append(p)

    selected_examples: list[DistillationPair] = []
    for m_pairs in by_mode.values():
        selected_examples.extend(m_pairs[-max_examples_per_mode:])

    for pair in selected_examples:
        user_msg = _sanitize_modelfile_text(f"Language hint: auto-detected\nMode: {pair.mode}\n\nTranscript:\n{pair.raw_text}")
        assistant_msg = json.dumps({"cleaned_text": pair.cleaned_text}, ensure_ascii=False)
        assistant_msg_clean = _sanitize_modelfile_text(assistant_msg)
        lines.append(f'MESSAGE user """{user_msg}"""')
        lines.append(f'MESSAGE assistant """{assistant_msg_clean}"""\n')

    return "\n".join(lines)


def write_modelfile(
    output_path: Path,
    base_model: str = DEFAULT_BASE_MODEL,
    mode: str = "all",
    pairs: Sequence[DistillationPair] = (),
) -> Path:
    content = build_modelfile(base_model=base_model, mode=mode, pairs=pairs)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(content, encoding="utf-8")
    return output_path


def create_ollama_model(
    model_name: str = DEFAULT_DISTILLED_MODEL_NAME,
    modelfile_content: str = "",
    base_url: str = "http://127.0.0.1:11434",
    timeout_seconds: float = 120.0,
) -> bool:
    """Send create request to local Ollama daemon."""
    payload = {
        "name": model_name,
        "modelfile": modelfile_content,
        "stream": False,
    }
    req = Request(
        f"{base_url.rstrip('/')}/api/create",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(req, timeout=timeout_seconds) as response:
            body = response.read().decode("utf-8")
            data = json.loads(body)
            if "error" in data:
                raise VoiceFlowError(f"Ollama creation error: {data['error']}")
            return data.get("status") == "success"
    except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        raise VoiceFlowError(f"Failed to create Ollama model '{model_name}': {exc}") from exc
