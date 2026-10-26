import os
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from sanbluedot_voiceflow.doctor import inspect_whisper_model, bundled_binary, bundled_model, run_checks


def write_model(
    path: Path,
    *,
    magic: bytes = b"lmgg",
    n_mels: int = 80,
    n_audio_layer: int = 12,
    padding: int = 80 * 201 * 4 + 51865 * 768 // 2,
) -> Path:
    """Write a ggml Whisper header shaped like the provisioned models."""
    header = magic + struct.pack(
        "<13i",
        51865,            # n_vocab
        1500,             # n_audio_ctx
        768,              # n_audio_state
        12,               # n_audio_head
        n_audio_layer,    # n_audio_layer
        448,              # n_text_ctx
        768,              # n_text_state
        12,               # n_text_head
        12,               # n_text_layer
        n_mels,           # n_mels
        1,                # ftype
        n_mels,           # mel filter bands
        201,              # mel filter fft bins
    )
    path.write_bytes(header + b"\0" * padding)
    return path


class FakeResponse:
    def __init__(self, body: bytes) -> None:
        self.body = body

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def read(self) -> bytes:
        return self.body


class WhisperModelInspectionTests(unittest.TestCase):
    def test_a_well_formed_model_passes_and_reports_its_shape(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            model = write_model(Path(temp_dir) / "ggml-small.bin")

            check = inspect_whisper_model(model)

        self.assertTrue(check.ok)
        self.assertIn("80 mel bands", check.detail)
        self.assertIn("12 audio layers", check.detail)

    def test_an_unconfigured_model_is_reported_without_crashing(self) -> None:
        check = inspect_whisper_model(None)

        self.assertFalse(check.ok)
        self.assertEqual(check.detail, "not configured")

    def test_a_missing_file_is_named(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            check = inspect_whisper_model(Path(temp_dir) / "absent.bin")

        self.assertFalse(check.ok)
        self.assertIn("not found", check.detail)

    def test_an_empty_file_no_longer_passes_as_a_model(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            model = Path(temp_dir) / "ggml-small.bin"
            model.touch()

            check = inspect_whisper_model(model)

        self.assertFalse(check.ok)
        self.assertIn("not a ggml Whisper model", check.detail)

    def test_a_downloaded_error_page_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            model = Path(temp_dir) / "ggml-small.bin"
            model.write_bytes(b"<html><body>404 Not Found</body></html>" * 4000)

            check = inspect_whisper_model(model)

        self.assertFalse(check.ok)
        self.assertIn("not a ggml Whisper model", check.detail)

    def test_an_interrupted_download_is_rejected_despite_a_valid_header(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            model = write_model(Path(temp_dir) / "ggml-small.bin", padding=32)

            check = inspect_whisper_model(model)

        self.assertFalse(check.ok)
        self.assertIn("truncated", check.detail)

    def test_a_partial_download_larger_than_the_mel_block_is_still_rejected(self) -> None:
        # 100 kB of a real ggml-small.bin passed while the floor covered only the mel
        # filter bank. The token-embedding floor is what makes this case fail.
        with tempfile.TemporaryDirectory() as temp_dir:
            model = write_model(Path(temp_dir) / "ggml-small.bin", padding=100_000)

            check = inspect_whisper_model(model)

        self.assertFalse(check.ok)
        self.assertIn("truncated", check.detail)

    def test_an_impossible_mel_band_count_is_corruption(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            model = write_model(Path(temp_dir) / "ggml-small.bin", n_mels=7)

            check = inspect_whisper_model(model)

        self.assertFalse(check.ok)
        self.assertIn("corrupt ggml header", check.detail)

    def test_a_foreign_magic_number_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            model = write_model(Path(temp_dir) / "ggml-small.bin", magic=b"GGUF")

            check = inspect_whisper_model(model)

        self.assertFalse(check.ok)
        self.assertIn("not a ggml Whisper model", check.detail)

    def test_run_checks_carries_the_model_verdict(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            model = Path(temp_dir) / "ggml-small.bin"
            model.touch()
            with patch(
                "sanbluedot_voiceflow.doctor.resolve_binary",
                return_value=Path("/usr/local/bin/whisper-cli"),
            ):
                checks = run_checks(
                    whisper_binary="whisper-cli",
                    whisper_model=model,
                )

        model_check = next(check for check in checks if check.name == "Whisper model")
        self.assertFalse(model_check.ok)


class BundledDependencyTests(unittest.TestCase):
    """The adapter keeps the binary and the weights beside the sources, not on PATH."""

    def test_the_projects_own_binary_wins_over_a_path_lookup(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self.assertEqual(bundled_binary("whisper-cli", root), "whisper-cli")
            installed = root / ("whisper-cli.exe" if os.name == "nt" else "whisper-cli")
            installed.touch()
            self.assertEqual(bundled_binary("whisper-cli", root), str(installed))

    def test_an_absent_model_still_reads_as_unconfigured(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            # None rather than a guessed path: a name that is not there must not be
            # reported as a model that failed its header check.
            self.assertIsNone(bundled_model(root))
            (root / "ggml-large-v3-turbo.bin").touch()
            self.assertEqual(bundled_model(root), root / "ggml-large-v3-turbo.bin")
            # Base is the adapter's first choice, so it wins once both are installed.
            (root / "ggml-base.bin").touch()
            self.assertEqual(bundled_model(root), root / "ggml-base.bin")


class DoctorTests(unittest.TestCase):
    def test_wrong_shape_ollama_json_is_reported_without_crashing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            model = Path(temp_dir) / "model.bin"
            model.touch()
            with (
                patch(
                    "sanbluedot_voiceflow.doctor.resolve_binary",
                    return_value=Path("/usr/local/bin/whisper-cli"),
                ),
                patch(
                    "sanbluedot_voiceflow.doctor.urlopen",
                    return_value=FakeResponse(b"[]"),
                ),
            ):
                checks = run_checks(
                    whisper_binary="whisper-cli",
                    whisper_model=model,
                    ollama_url="http://127.0.0.1:11434",
                    ollama_model="qwen3:4b",
                )

        ollama = next(check for check in checks if check.name == "Ollama")
        self.assertFalse(ollama.ok)
        self.assertEqual(ollama.detail, "service not reachable")


if __name__ == "__main__":
    unittest.main()


class MacHelperCheckTests(unittest.TestCase):
    """D-44: doctor names the Mac helpers, not only Whisper."""

    def test_the_helpers_are_listed(self) -> None:
        from sanbluedot_voiceflow.doctor import run_checks

        names = [check.name for check in run_checks(
            whisper_binary="whisper-cli", whisper_model=None, mac_helpers=True
        )]
        for expected in ("Apple cleanup helper", "Parakeet helper", "pbcopy", "Parakeet model", "Gemini API key"):
            self.assertIn(expected, names)
