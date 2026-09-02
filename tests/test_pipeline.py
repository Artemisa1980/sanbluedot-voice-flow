import unittest
from pathlib import Path

from sanbluedot_voiceflow.contracts import Transcript
from sanbluedot_voiceflow.errors import CleanupFailed
from sanbluedot_voiceflow.memory import Correction
from sanbluedot_voiceflow.pipeline import DictationPipeline


class FakeTranscriber:
    def __init__(self, text: str, language: str | None = None) -> None:
        self.transcript = Transcript(text=text, language=language)

    def transcribe(self, audio_path: Path) -> Transcript:
        del audio_path
        return self.transcript


class FakeCleaner:
    name = "fake"

    def __init__(self, result: str | None = None, error: Exception | None = None) -> None:
        self.result = result
        self.error = error
        self.language_hint: str | None = None

    def clean(self, text: str, language_hint: str | None = None) -> str:
        self.language_hint = language_hint
        if self.error:
            raise self.error
        return self.result if self.result is not None else text


class DictationPipelineTests(unittest.TestCase):
    def test_returns_raw_and_cleaned_text(self) -> None:
        cleaner = FakeCleaner(result="Hello, world.")
        pipeline = DictationPipeline(FakeTranscriber("hello um world", "en"), cleaner)

        result = pipeline.process(Path("unused.wav"))

        self.assertEqual(result.raw_text, "hello um world")
        self.assertEqual(result.personalized_text, "hello um world")
        self.assertEqual(result.final_text, "Hello, world.")
        self.assertEqual(result.language, "en")
        self.assertEqual(cleaner.language_hint, "en")

    def test_cleanup_failure_retains_raw_transcript(self) -> None:
        pipeline = DictationPipeline(
            FakeTranscriber("texto original", "es"),
            FakeCleaner(error=RuntimeError("offline")),
        )

        with self.assertRaises(CleanupFailed) as raised:
            pipeline.process(Path("unused.wav"))

        self.assertEqual(raised.exception.raw_text, "texto original")
        self.assertEqual(raised.exception.fallback_text, "texto original")
        self.assertEqual(raised.exception.language, "es")

    def test_nonempty_transcript_rejects_empty_cleanup(self) -> None:
        pipeline = DictationPipeline(FakeTranscriber("keep me"), FakeCleaner(result="  "))

        with self.assertRaises(CleanupFailed) as raised:
            pipeline.process(Path("unused.wav"))

        self.assertEqual(raised.exception.raw_text, "keep me")

    def test_raw_and_personalized_transcripts_remain_distinct(self) -> None:
        correction = Correction("ies", "IESS", "2026-08-29T00:00:00+00:00")
        pipeline = DictationPipeline(
            FakeTranscriber("aporté al ies", "es"),
            FakeCleaner(),
            [correction],
        )

        result = pipeline.process(Path("unused.wav"))

        self.assertEqual(result.raw_text, "aporté al ies")
        self.assertEqual(result.personalized_text, "aporté al IESS")
        self.assertEqual(result.final_text, "aporté al IESS")

    def test_translate_mode_allows_new_language_content(self) -> None:
        cleaner = FakeCleaner(result="Hello world, this is a live test.")
        cleaner.mode = "translate"
        pipeline = DictationPipeline(FakeTranscriber("hola mundo esto es una prueba", "es"), cleaner)

        result = pipeline.process(Path("unused.wav"))

        self.assertEqual(result.raw_text, "hola mundo esto es una prueba")
        self.assertEqual(result.final_text, "Hello world, this is a live test.")

    def test_meeting_mode_allows_markdown_structure(self) -> None:
        cleaner = FakeCleaner(result="### Meeting Summary\n- [ ] Deploy v0.5.0\n- [ ] Review architecture")
        cleaner.mode = "meeting"
        pipeline = DictationPipeline(FakeTranscriber("hay que desplegar la versión 0.5 y revisar arquitectura", "es"), cleaner)

        result = pipeline.process(Path("unused.wav"))

        self.assertEqual(result.final_text, "### Meeting Summary\n- [ ] Deploy v0.5.0\n- [ ] Review architecture")

    def test_clean_mode_allows_multi_sentence_periods(self) -> None:
        cleaner = FakeCleaner(result="We will deploy today. It is ready.")
        cleaner.mode = "clean"
        pipeline = DictationPipeline(FakeTranscriber("we will deploy today it is ready", "en"), cleaner)

        result = pipeline.process(Path("unused.wav"))

        self.assertEqual(result.final_text, "We will deploy today. It is ready.")


class PipelineTimingTests(unittest.TestCase):
    """A reported latency must be the one the run measured."""

    def test_each_stage_reports_its_own_measured_duration(self) -> None:
        ticks = iter([100.0, 101.5, 101.5, 104.0])
        pipeline = DictationPipeline(
            FakeTranscriber("hola", "es"),
            FakeCleaner(result="Hola."),
            monotonic=lambda: next(ticks),
        )

        result = pipeline.process(Path("unused.wav"))

        self.assertAlmostEqual(result.transcribe_seconds, 1.5)
        self.assertAlmostEqual(result.cleanup_seconds, 2.5)

    def test_a_cleanup_failure_carries_both_measurements(self) -> None:
        ticks = iter([10.0, 11.0, 11.0, 56.0])
        pipeline = DictationPipeline(
            FakeTranscriber("hola", "es"),
            FakeCleaner(error=RuntimeError("provider timed out")),
            monotonic=lambda: next(ticks),
        )

        with self.assertRaises(CleanupFailed) as raised:
            pipeline.process(Path("unused.wav"))

        self.assertAlmostEqual(raised.exception.transcribe_seconds, 1.0)
        self.assertAlmostEqual(raised.exception.cleanup_seconds, 45.0)


if __name__ == "__main__":
    unittest.main()
