import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import urlopen

from .transcribers import resolve_binary


@dataclass(frozen=True, slots=True)
class Check:
    name: str
    ok: bool
    detail: str


# whisper.cpp stores the ggml magic 0x67676d6c little-endian, then eleven int32
# hyper-parameters, then the mel filter bank header. Verified against the provisioned
# ggml-small.bin and ggml-large-v3-turbo.bin on this machine.
GGML_MAGIC = b"lmgg"
HEADER_SIZE = 4 + 11 * 4 + 8
# Whisper uses 80 mel bands, or 128 from large-v3 onward. Any other value is corruption,
# not a newer model.
SUPPORTED_MEL_BANDS = (80, 128)


def inspect_whisper_model(model_path: Path | None) -> Check:
    """Report whether the configured model is a readable ggml Whisper model.

    Presence alone accepted an empty file, an interrupted download and an HTML error
    page saved under a `.bin` name, so the failure only appeared as an unusable
    dictation. Reading the header names the bad file before a recording is lost to it.

    This is a format and size check. It cannot prove the weights are bit-perfect, and
    a file truncated above the derived floor still passes; both would need a recorded
    hash baseline, which this project does not keep.
    """
    if model_path is None:
        return Check("Whisper model", False, "not configured")

    path = model_path.expanduser()
    if not path.is_file():
        return Check("Whisper model", False, f"not found: {path}")

    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            header = handle.read(HEADER_SIZE)
    except OSError as exc:
        return Check("Whisper model", False, f"unreadable: {path} ({exc})")

    if len(header) < HEADER_SIZE or header[:4] != GGML_MAGIC:
        return Check("Whisper model", False, f"not a ggml Whisper model: {path}")

    fields = struct.unpack("<13i", header[4:HEADER_SIZE])
    dimensions = fields[:9]
    n_vocab, n_audio_layer, n_text_state = fields[0], fields[4], fields[6]
    n_mels, ftype, n_mel_filters, n_fft = fields[9], fields[10], fields[11], fields[12]
    if min(dimensions) <= 0 or n_mels not in SUPPORTED_MEL_BANDS or ftype < 0:
        return Check("Whisper model", False, f"corrupt ggml header: {path}")
    if n_mel_filters <= 0 or n_fft <= 0:
        return Check("Whisper model", False, f"corrupt ggml header: {path}")

    # Floor derived from the file's own header rather than from a remembered download
    # size: the mel filter bank, plus the token embedding matrix of n_vocab ×
    # n_text_state values. Four-bit quantisation still spends half a byte per value, so
    # a file under this floor cannot hold the weights its header describes. A partial
    # download that kept a valid header is the case this catches.
    minimum = HEADER_SIZE + n_mel_filters * n_fft * 4 + n_vocab * n_text_state // 2
    if size < minimum:
        return Check(
            "Whisper model",
            False,
            f"truncated ggml model: {path} "
            f"({size / 1_000_000:.1f} MB, header needs at least "
            f"{minimum / 1_000_000:.1f} MB)",
        )

    return Check(
        "Whisper model",
        True,
        f"{path} (ggml, {n_audio_layer} audio layers, {n_mels} mel bands, "
        f"{size / 1_000_000:.0f} MB)",
    )


# The engine is also driven by the Windows adapter, which keeps the binary and the
# weights beside the sources and passes both as absolute paths. `doctor` resolved only
# through PATH and an explicit flag, so it reported both as missing on the machine where
# they were installed, and could not diagnose the surface under repair.
PROJECT_MODELS = Path(__file__).resolve().parents[2] / "models"
# Base first, then the larger candidate, matching how the adapter picks a default.
BUNDLED_MODELS = ("ggml-base.bin", "ggml-large-v3-turbo.bin")


def bundled_binary(name: str, directory: Path = PROJECT_MODELS) -> str:
    """The project's own copy of `name`, or `name` unchanged for a PATH lookup."""
    for candidate in (directory / f"{name}.exe", directory / name):
        if candidate.is_file():
            return str(candidate)
    return name


def bundled_model(directory: Path = PROJECT_MODELS) -> Path | None:
    """The first installed candidate, or None so an absent one still reads as unconfigured."""
    for name in BUNDLED_MODELS:
        candidate = directory / name
        if candidate.is_file():
            return candidate
    return None


def ollama_status(base_url: str, model: str | None = None, timeout: float = 1.5) -> dict:
    """Whether the local service answers, and which models it already holds.

    Reads the service's own inventory and nothing else: it never pulls a model, and a
    service that does not answer is reported as unreachable rather than as a missing
    model, because the two call for different things from the reader.
    """
    try:
        with urlopen(f"{base_url.rstrip('/')}/api/tags", timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("Ollama returned a non-object response.")
        entries = payload.get("models", [])
        if not isinstance(entries, list):
            raise ValueError("Ollama returned a non-list models field.")
        names = sorted(
            entry["name"]
            for entry in entries
            if isinstance(entry, dict) and isinstance(entry.get("name"), str)
        )
    except (
        HTTPError,
        URLError,
        TimeoutError,
        OSError,
        UnicodeDecodeError,
        json.JSONDecodeError,
        TypeError,
        ValueError,
    ):
        return {
            "reachable": False,
            "models": [],
            "model": model,
            "ready": False,
            "state": "unreachable",
            "detail": "service not reachable",
        }

    # The caller needs to tell these apart to say anything useful, and matching on the
    # sentence below would break the moment its wording improved.
    if model is None and not names:
        state, detail = "no_model_installed", "service available; no model installed"
    elif model is None:
        state, detail = "no_model_chosen", f"service available; {len(names)} model(s) installed"
    elif model in names:
        state, detail = "ready", f"available with {model}"
    else:
        state, detail = "model_missing", f"service available; model not installed: {model}"
    return {
        "reachable": True,
        "models": names,
        "model": model,
        "ready": state == "ready",
        "state": state,
        "detail": detail,
    }


def run_checks(
    *,
    whisper_binary: str,
    whisper_model: Path | None,
    ollama_url: str = "http://127.0.0.1:11434",
    ollama_model: str | None = None,
    mac_helpers: bool = False,
) -> list[Check]:
    """Check what a dictation needs. Ollama is checked only when a model is named.

    Ollama left the macOS app on 2026-10-01 and stays in the engine for the Windows
    adapter, which has no on-device model of its own, so `cli.py` names one only there.
    """
    checks = [
        Check(
            "Python",
            sys.version_info >= (3, 11),
            f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
        )
    ]

    binary_path = resolve_binary(whisper_binary)
    checks.append(
        Check(
            "whisper.cpp binary",
            binary_path is not None,
            str(binary_path) if binary_path else f"not found: {whisper_binary}",
        )
    )

    checks.append(inspect_whisper_model(whisper_model))

    # The Mac's other engines: `doctor` checked Whisper only, so a missing Apple or
    # Parakeet helper surfaced as a failed dictation (D-44).
    if mac_helpers:
        from .cleaners.apple import DEFAULT_BINARY as APPLE_BINARY
        from .transcribers.parakeet import DEFAULT_BINARY as PARAKEET_BINARY
        from .transcribers.parakeet import DEFAULT_MODEL_DIR as PARAKEET_MODELS

        for name, binary in (("Apple cleanup helper", APPLE_BINARY),
                             ("Parakeet helper", PARAKEET_BINARY),
                             ("pbcopy", "pbcopy")):
            found = resolve_binary(binary)
            detail = str(found) if found else (
                f"not on PATH: {binary} (the app carries its own copy; this shell does not)"
            )
            checks.append(Check(name, found is not None, detail))
        checks.append(
            Check(
                "Parakeet model",
                PARAKEET_MODELS.is_dir() and any(PARAKEET_MODELS.iterdir()),
                str(PARAKEET_MODELS.resolve()),
            )
        )
        from .credentials import read_api_key

        has_gemini = read_api_key("gemini") is not None
        checks.append(
            Check(
                "Gemini API key",
                has_gemini,
                "configured in keychain or environment" if has_gemini else "no key configured",
            )
        )

    if ollama_model is not None:
        status = ollama_status(ollama_url, ollama_model)
        checks.append(Check("Ollama", status["ready"], status["detail"]))

    return checks
