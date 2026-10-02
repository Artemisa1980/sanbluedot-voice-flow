import struct
import sys
from dataclasses import dataclass
from pathlib import Path

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


def run_checks(
    *,
    whisper_binary: str,
    whisper_model: Path | None,
) -> list[Check]:
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
    return checks
