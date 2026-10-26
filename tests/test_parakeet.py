import argparse
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from sanbluedot_voiceflow import cli
from sanbluedot_voiceflow.errors import DependencyUnavailable, TranscriptionError
from sanbluedot_voiceflow.transcribers.parakeet import ParakeetTranscriber


class ParakeetTranscriberTests(unittest.TestCase):
    def _setup(self, root: Path) -> tuple[Path, Path, Path]:
        binary, models, audio = root / "voiceflow-parakeet", root / "models", root / "a.wav"
        binary.touch()
        binary.chmod(0o755)
        models.mkdir()
        audio.touch()
        return binary, models, audio

    def test_reads_the_last_line_and_reports_no_language(self) -> None:
        commands: list[list[str]] = []
        with tempfile.TemporaryDirectory() as temp_dir:
            binary, models, audio = self._setup(Path(temp_dir))

            def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
                commands.append(command)
                stdout = 'library notice\n{"text": " Hola, I need el reporte. "}\n'
                return subprocess.CompletedProcess(command, 0, stdout, "")

            result = ParakeetTranscriber(models, str(binary), runner=runner).transcribe(audio)

        self.assertEqual(result.text, "Hola, I need el reporte.")
        self.assertIsNone(result.language)
        self.assertEqual(commands[0][1:3], ["--models", str(models.resolve())])
        self.assertEqual(commands[0][-1], str(audio.resolve()))

    def test_a_missing_model_is_a_missing_dependency_not_a_failed_transcript(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            binary, models, audio = self._setup(Path(temp_dir))

            def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
                return subprocess.CompletedProcess(command, 2, "", "Fetch it once with --download.")

            with self.assertRaises(DependencyUnavailable) as raised:
                ParakeetTranscriber(models, str(binary), runner=runner).transcribe(audio)
        self.assertIn("--download", str(raised.exception))

    def test_a_model_directory_that_does_not_exist_is_named(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            binary, _, audio = self._setup(Path(temp_dir))
            with self.assertRaises(DependencyUnavailable):
                ParakeetTranscriber(Path(temp_dir) / "absent", str(binary)).transcribe(audio)

    def test_failure_garbage_and_empty_text_are_transcription_errors(self) -> None:
        replies = [
            (1, "", "the encoder failed"),
            (0, "not json", ""),
            (0, '{"text": "   "}', ""),
            (0, "", ""),
        ]
        for status, stdout, stderr in replies:
            with self.subTest(status=status, stdout=stdout), tempfile.TemporaryDirectory() as d:
                binary, models, audio = self._setup(Path(d))

                def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
                    return subprocess.CompletedProcess(command, status, stdout, stderr)

                with self.assertRaises(TranscriptionError):
                    ParakeetTranscriber(models, str(binary), runner=runner).transcribe(audio)

    def test_a_timeout_is_reported_as_one(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            binary, models, audio = self._setup(Path(temp_dir))

            def runner(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
                raise subprocess.TimeoutExpired(command, kwargs["timeout"])

            with self.assertRaises(TranscriptionError) as raised:
                ParakeetTranscriber(models, str(binary), runner=runner).transcribe(audio)
        self.assertIn("did not finish", str(raised.exception))

    def test_json_parsed_correctly_with_trailing_diagnostic_logs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            binary, models, audio = self._setup(Path(temp_dir))

            def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
                stdout = 'Loading CoreML...\n{"text": "Hola mundo"}\nMetal validation disabled.\nXPC connection finished.\n'
                return subprocess.CompletedProcess(command, 0, stdout, "")

            transcript = ParakeetTranscriber(models, str(binary), runner=runner).transcribe(audio)
            self.assertEqual(transcript.text, "Hola mundo")


class ProcessWithParakeetTests(unittest.TestCase):
    def _args(self, **overrides: object) -> argparse.Namespace:
        values: dict[str, object] = {
            "audio": Path("a.wav"),
            "transcriber": "parakeet",
            "whisper_bin": "whisper-cli",
            "whisper_model": None,
            "parakeet_bin": "voiceflow-parakeet",
            "parakeet_models": Path("models/fluidaudio/parakeet-ultra"),
            "language": "auto",
            "cleaner": "literal",
            "mode": "clean",
            "gemini_model": "gemini-3.8-flash",
            "copy": False,
            "json": False,
            "no_memory": True,
            "no_vocab_prompt": False,
            "distill": False,
        }
        values.update(overrides)
        return argparse.Namespace(**values)

    def test_parakeet_needs_no_whisper_model_and_reads_no_vocabulary(self) -> None:
        built: list[object] = []

        class FakeParakeet:
            def __init__(self, **kwargs: object) -> None:
                built.append(kwargs)

            def transcribe(self, _audio: Path):
                from sanbluedot_voiceflow.contracts import Transcript

                return Transcript(text="Hola, I need el reporte.")

        with patch.object(cli, "ParakeetTranscriber", FakeParakeet), patch.object(
            cli, "load_vocabulary"
        ) as vocabulary, patch("builtins.print"):
            status = cli._process(self._args())

        self.assertEqual(status, 0)
        self.assertEqual(built[0]["model_dir"], Path("models/fluidaudio/parakeet-ultra"))
        vocabulary.assert_not_called()

    def test_whisper_still_requires_its_model(self) -> None:
        with patch("builtins.print"):
            status = cli._process(self._args(transcriber="whisper"))
        self.assertEqual(status, 1)


if __name__ == "__main__":
    unittest.main()
