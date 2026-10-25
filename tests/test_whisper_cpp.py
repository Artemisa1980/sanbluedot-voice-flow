import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from sanbluedot_voiceflow.errors import DependencyUnavailable, TranscriptionError
from sanbluedot_voiceflow.transcribers.whisper_cpp import (
    WhisperCppTranscriber,
    detected_language,
    is_effectively_silent,
    resolve_binary,
)


# A stand-in binary has to be one the resolver accepts on the platform running the tests.
# POSIX decides by mode and Windows by extension, so the name carries `.exe` there.
BINARY_NAME = "whisper-cli.exe" if os.name == "nt" else "whisper-cli"


class WhisperCppTranscriberTests(unittest.TestCase):
    def test_builds_command_and_reads_generated_transcript(self) -> None:
        commands: list[list[str]] = []

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary = root / BINARY_NAME
            model = root / "model.bin"
            audio = root / "sample.wav"
            binary.touch()
            binary.chmod(0o755)
            model.touch()
            audio.touch()

            def runner(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
                commands.append(command)
                output_base = Path(command[command.index("-of") + 1])
                Path(f"{output_base}.txt").write_text(
                    "  Hola, world.  \n",
                    encoding="utf-8",
                )
                return subprocess.CompletedProcess(command, 0, "", "")

            transcriber = WhisperCppTranscriber(
                model_path=model,
                binary=str(binary),
                language="auto",
                runner=runner,
            )
            result = transcriber.transcribe(audio)

        self.assertEqual(result.text, "  Hola, world.  ")
        self.assertIsNone(result.language)
        self.assertEqual(commands[0][commands[0].index("-l") + 1], "auto")
        self.assertIn("-otxt", commands[0])

    def test_segments_on_separate_lines_are_joined_into_one_text(self) -> None:
        """A line break is where whisper paused; delivered, it chopped the dictation."""
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary, model, audio = root / "whisper-cli", root / "model.bin", root / "s.wav"
            for path in (binary, model, audio):
                path.touch()
            binary.chmod(0o755)

            def runner(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
                Path(f"{command[command.index('-of') + 1]}.txt").write_text(
                    " Ok, voy a comenzar con literal\n We want to change languages\n\n So, let's see\n",
                    encoding="utf-8",
                )
                return subprocess.CompletedProcess(command, 0, "", "")

            result = WhisperCppTranscriber(
                model_path=model, binary=str(binary), runner=runner
            ).transcribe(audio)

        self.assertEqual(
            result.text,
            "Ok, voy a comenzar con literal We want to change languages So, let's see",
        )

    def _transcribe_file_text(self, written: str):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary, model, audio = root / BINARY_NAME, root / "model.bin", root / "s.wav"
            for path in (binary, model, audio):
                path.touch()
            binary.chmod(0o755)

            def runner(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
                Path(f"{command[command.index('-of') + 1]}.txt").write_text(
                    written, encoding="utf-8"
                )
                return subprocess.CompletedProcess(command, 0, "", "")

            return WhisperCppTranscriber(
                model_path=model, binary=str(binary), runner=runner
            ).transcribe(audio)

    def test_a_transcript_of_only_non_speech_tags_is_no_speech(self) -> None:
        """A cough that passes the noise gate came back as `[BLANK_AUDIO]` and was pasted."""
        for written in (" [BLANK_AUDIO]\n", " (coughing)\n", " [BLANK_AUDIO]\n (tos)\n"):
            with self.subTest(written=written):
                with self.assertRaises(TranscriptionError):
                    self._transcribe_file_text(written)

    def test_a_tag_inside_real_speech_is_kept(self) -> None:
        result = self._transcribe_file_text(" Hola (en serio) mundo\n")
        self.assertEqual(result.text, " Hola (en serio) mundo")

    def test_automatic_mode_recovers_the_language_whisper_detected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary, model, audio = root / BINARY_NAME, root / "model.bin", root / "s.wav"
            for path in (binary, model, audio):
                path.touch()
            binary.chmod(0o755)

            def runner(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
                Path(f"{command[command.index('-of') + 1]}.txt").write_text(
                    "Hola.",
                    encoding="utf-8",
                )
                return subprocess.CompletedProcess(
                    command,
                    0,
                    "",
                    "whisper_full_with_state: auto-detected language: es (p = 0.98)\n",
                )

            result = WhisperCppTranscriber(
                model,
                binary=str(binary),
                language="auto",
                runner=runner,
            ).transcribe(audio)

        self.assertEqual(result.language, "es")

    def test_an_explicit_language_ignores_engine_detection_output(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary, model, audio = root / BINARY_NAME, root / "model.bin", root / "s.wav"
            for path in (binary, model, audio):
                path.touch()
            binary.chmod(0o755)

            def runner(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
                Path(f"{command[command.index('-of') + 1]}.txt").write_text(
                    "Hello.",
                    encoding="utf-8",
                )
                return subprocess.CompletedProcess(
                    command,
                    0,
                    "",
                    "auto-detected language: es (p = 0.51)\n",
                )

            result = WhisperCppTranscriber(
                model,
                binary=str(binary),
                language="en",
                runner=runner,
            ).transcribe(audio)

        self.assertEqual(result.language, "en")

    def test_a_runner_without_captured_output_reports_an_unknown_language(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary, model, audio = root / BINARY_NAME, root / "model.bin", root / "s.wav"
            for path in (binary, model, audio):
                path.touch()
            binary.chmod(0o755)

            def runner(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
                Path(f"{command[command.index('-of') + 1]}.txt").write_text(
                    "Hola.",
                    encoding="utf-8",
                )
                return subprocess.CompletedProcess(command, 0, None, None)  # type: ignore[arg-type]

            result = WhisperCppTranscriber(
                model,
                binary=str(binary),
                language="auto",
                runner=runner,
            ).transcribe(audio)

        self.assertIsNone(result.language)

    def test_reports_the_useful_tail_of_whisper_error(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary = root / BINARY_NAME
            model = root / "model.bin"
            audio = root / "sample.wav"
            binary.touch()
            binary.chmod(0o755)
            model.touch()
            audio.touch()

            def runner(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
                raise subprocess.CalledProcessError(
                    1,
                    command,
                    stderr=("backend noise\n" * 100) + "decisive failure",
                )

            transcriber = WhisperCppTranscriber(model, binary=str(binary), runner=runner)

            with self.assertRaises(TranscriptionError) as raised:
                transcriber.transcribe(audio)

        self.assertIn("decisive failure", str(raised.exception))


    def test_tuning_flags_appear_only_when_set(self) -> None:
        commands: list[list[str]] = []

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary, model, audio = root / BINARY_NAME, root / "model.bin", root / "s.wav"
            for path in (binary, model, audio):
                path.touch()
            binary.chmod(0o755)

            def runner(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
                commands.append(command)
                Path(f"{command[command.index('-of') + 1]}.txt").write_text("ok", encoding="utf-8")
                return subprocess.CompletedProcess(command, 0, "", "")

            WhisperCppTranscriber(model, binary=str(binary), runner=runner).transcribe(audio)
            WhisperCppTranscriber(
                model,
                binary=str(binary),
                initial_prompt="UTEL, Gim",
                threads=8,
                beam_size=5,
                runner=runner,
            ).transcribe(audio)

        self.assertNotIn("-t", commands[0])
        self.assertNotIn("-bs", commands[0])
        self.assertNotIn("--prompt", commands[0])
        self.assertEqual(commands[1][commands[1].index("-t") + 1], "8")
        self.assertEqual(commands[1][commands[1].index("-bs") + 1], "5")
        self.assertEqual(commands[1][commands[1].index("--prompt") + 1], "UTEL, Gim")

    def test_a_hung_whisper_becomes_a_transcription_error(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary = root / BINARY_NAME
            model = root / "model.bin"
            audio = root / "sample.wav"
            binary.touch()
            binary.chmod(0o755)
            model.touch()
            audio.touch()

            def runner(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
                raise subprocess.TimeoutExpired(command, float(kwargs["timeout"]))  # type: ignore[arg-type]

            transcriber = WhisperCppTranscriber(
                model,
                binary=str(binary),
                timeout_seconds=7.0,
                runner=runner,
            )

            with self.assertRaises(TranscriptionError) as raised:
                transcriber.transcribe(audio)

        self.assertIn("7 seconds", str(raised.exception))

    def test_invalid_transcript_encoding_becomes_a_transcription_error(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary, model, audio = root / BINARY_NAME, root / "model.bin", root / "s.wav"
            for path in (binary, model, audio):
                path.touch()
            binary.chmod(0o755)

            def runner(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
                Path(f"{command[command.index('-of') + 1]}.txt").write_bytes(b"hello\xff")
                return subprocess.CompletedProcess(command, 0, "", "")

            with self.assertRaises(TranscriptionError):
                WhisperCppTranscriber(model, binary=str(binary), runner=runner).transcribe(audio)

    def test_transcript_read_failure_becomes_a_transcription_error(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary, model, audio = root / BINARY_NAME, root / "model.bin", root / "s.wav"
            for path in (binary, model, audio):
                path.touch()
            binary.chmod(0o755)

            def runner(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
                Path(f"{command[command.index('-of') + 1]}.txt").write_text(
                    "hello",
                    encoding="utf-8",
                )
                return subprocess.CompletedProcess(command, 0, "", "")

            with patch.object(Path, "read_text", side_effect=OSError("denied")):
                with self.assertRaises(TranscriptionError):
                    WhisperCppTranscriber(
                        model,
                        binary=str(binary),
                        runner=runner,
                    ).transcribe(audio)

    @unittest.skipIf(
        os.name == "nt",
        "Windows does not deny the file's owner read access through chmod",
    )
    def test_unreadable_model_raises_dependency_unavailable(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary, model, audio = root / BINARY_NAME, root / "model.bin", root / "s.wav"
            for path in (binary, model, audio):
                path.touch()
            binary.chmod(0o755)

            model.chmod(0o000)
            try:
                transcriber = WhisperCppTranscriber(model, binary=str(binary))
                with self.assertRaises(DependencyUnavailable) as ctx:
                    transcriber.transcribe(audio)
                self.assertIn("not readable", str(ctx.exception))
            finally:
                model.chmod(0o644)


class DetectedLanguageTests(unittest.TestCase):
    def test_the_last_reported_detection_wins(self) -> None:
        completed = subprocess.CompletedProcess(
            ["whisper-cli"],
            0,
            "",
            "auto-detected language: en (p = 0.40)\n"
            "auto-detected language: es (p = 0.93)\n",
        )

        self.assertEqual(detected_language(completed), "es")

    def test_stdout_is_read_when_the_build_logs_there(self) -> None:
        completed = subprocess.CompletedProcess(
            ["whisper-cli"],
            0,
            "auto-detected language: EN (p = 0.71)\n",
            "",
        )

        self.assertEqual(detected_language(completed), "en")

    def test_output_without_a_detection_line_stays_unknown(self) -> None:
        completed = subprocess.CompletedProcess(["whisper-cli"], 0, "", "loading model\n")

        self.assertIsNone(detected_language(completed))


class SilenceGuardTests(unittest.TestCase):
    def write_wav(self, path: Path, amplitude: int, frames: int = 16000) -> Path:
        import array
        import wave

        with wave.open(str(path), "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(16000)
            handle.writeframes(
                array.array("h", [amplitude if i % 2 else -amplitude
                                  for i in range(frames)]).tobytes()
            )
        return path

    def write_samples(self, path: Path, samples: list[float]) -> Path:
        import array
        import wave

        with wave.open(str(path), "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(16000)
            handle.writeframes(array.array(
                "h", [max(-32768, min(32767, int(value * 32767))) for value in samples]
            ).tobytes())
        return path

    def syllables(self, level: float, duty: float = 0.6, seconds: float = 2.0) -> list[float]:
        """Bursts at `level` filling `duty` of every 250 ms, split by pauses, like words."""
        samples = []
        for index in range(int(16000 * seconds)):
            loud = (index % 4000) < 4000 * duty
            samples.append((level if index % 2 else -level) if loud else 0.0)
        return samples

    def noise(self, level: float, seconds: float = 2.0) -> list[float]:
        import random

        generator = random.Random(7)
        return [generator.gauss(0.0, level) for _ in range(int(16000 * seconds))]

    def test_silence_is_rejected_before_the_engine_can_invent_text(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            quiet = self.write_wav(Path(temp_dir) / "quiet.wav", 0)

            self.assertTrue(is_effectively_silent(quiet))

    def test_a_real_recording_level_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            # The owner's quietest measured take sits near 0.020 RMS.
            speech = self.write_samples(Path(temp_dir) / "speech.wav", self.syllables(0.020))

            self.assertFalse(is_effectively_silent(speech))

    def test_steady_noise_without_speech_is_rejected(self) -> None:
        # Whisper turned this level of steady noise into "and the rest of the world."
        with tempfile.TemporaryDirectory() as temp_dir:
            hum = self.write_samples(Path(temp_dir) / "hum.wav", self.noise(0.012))

            self.assertTrue(is_effectively_silent(hum))

    def test_speech_under_noise_louder_than_the_voice_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            # Real speech is peaky: about 0.025 RMS overall with loud frames near 0.05.
            voice, hum = self.syllables(0.05, duty=0.25), self.noise(0.030)
            mixed = self.write_samples(
                Path(temp_dir) / "mixed.wav", [a + b for a, b in zip(voice, hum)]
            )

            self.assertFalse(is_effectively_silent(mixed))

    def test_a_level_inside_the_rejected_band_is_still_silence(self) -> None:
        # The cases above sit at 0 and at 0.020 RMS, and both answer the same way
        # whatever the floor is set to, so neither one measures the floor. This level
        # sits between them, where the floor is the only thing deciding: a floor moved
        # away from SILENCE_RMS fails here instead of passing unnoticed.
        with tempfile.TemporaryDirectory() as temp_dir:
            faint = self.write_wav(Path(temp_dir) / "faint.wav", int(0.001 * 32768))

            self.assertTrue(is_effectively_silent(faint))

    def test_a_level_just_above_the_floor_is_accepted(self) -> None:
        # Spoken, not a steady tone: a tone at any level is refused as steady noise
        # (D-53). These syllables average about 0.004 RMS, just above the floor.
        with tempfile.TemporaryDirectory() as temp_dir:
            soft = self.write_samples(Path(temp_dir) / "soft.wav", self.syllables(0.005))

            self.assertFalse(is_effectively_silent(soft))

    def test_unreadable_audio_fails_open_rather_than_blocking(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            broken = Path(temp_dir) / "broken.wav"
            broken.write_bytes(b"not a wav at all")

            self.assertFalse(is_effectively_silent(broken))

    def test_silent_audio_never_reaches_the_engine(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            binary, model = root / BINARY_NAME, root / "model.bin"
            binary.touch()
            binary.chmod(0o755)
            model.touch()
            audio = self.write_wav(root / "quiet.wav", 0)
            called: list[list[str]] = []

            def runner(command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
                called.append(command)
                return subprocess.CompletedProcess(command, 0, "", "")

            with self.assertRaises(TranscriptionError):
                WhisperCppTranscriber(model, binary=str(binary), runner=runner).transcribe(audio)

            self.assertEqual(called, [])


class BinaryResolutionTests(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "chmod does not remove execute permission on Windows")
    def test_explicit_binary_must_be_executable(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            binary = Path(temp_dir) / "whisper-cli"
            binary.write_text("not executable", encoding="utf-8")

            self.assertIsNone(resolve_binary(str(binary)))
            binary.chmod(0o755)
            self.assertEqual(resolve_binary(str(binary)), binary.resolve())

    @unittest.skipUnless(os.name == "nt", "PATHEXT is what decides executability on Windows")
    def test_explicit_binary_must_carry_an_executable_extension(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            rejected = Path(temp_dir) / "whisper-cli"
            accepted = Path(temp_dir) / "whisper-cli.exe"
            rejected.write_text("not executable", encoding="utf-8")
            accepted.write_text("stands in for the real binary", encoding="utf-8")

            self.assertIsNone(resolve_binary(str(rejected)))
            self.assertEqual(resolve_binary(str(accepted)), accepted.resolve())


if __name__ == "__main__":
    unittest.main()
