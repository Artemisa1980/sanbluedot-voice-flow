import unittest

from sanbluedot_voiceflow.cleaners import LiteralCleaner
from sanbluedot_voiceflow.pipeline import DictationPipeline
from sanbluedot_voiceflow.take_back import has_take_back


class TakeBackPhraseTests(unittest.TestCase):
    def test_spoken_take_backs_are_found_in_either_language(self) -> None:
        for text in (
            "quiero probar algo, no, mejor no, borra eso y comencemos",
            "Me equivoqué, el lunes no, el martes",
            "a las tres, perdón, no, a las cuatro",
            "let's meet at three, scratch that, at four",
            "send it to John, sorry, no, to Mark",
            # The two a dictation on 2026-09-27 slipped past.
            "La reunión va a ser a las 4, no, no, no, perdón, va a ser a las 5 p.m.",
            "is you cool, no, scratch the first, you cool",
        ):
            with self.subTest(text=text):
                self.assertTrue(has_take_back(text))

    def test_ordinary_negatives_are_not_take_backs(self) -> None:
        """A bare "no" or "digo" is speech; asking the model about every one of them would
        cost nearly every sentence a second call."""
        for text in (
            "no quiero que envíes el correo todavía",
            "te digo que sí vamos mañana",
            "I don't want to send it yet, no rush",
        ):
            with self.subTest(text=text):
                self.assertFalse(has_take_back(text))


class _RecordingCleaner:
    """A model cleaner that answers per mode and records the modes it ran in."""

    name = "fake"

    def __init__(self, answer, mode: str = "clean") -> None:
        self.answers = answer if isinstance(answer, dict) else None
        self.answer = answer
        self.mode = mode
        self.modes: list[str] = []

    def clean(self, text, language_hint=None, mode=None):
        active = mode or self.mode
        self.modes.append(active)
        return self.answers[active] if self.answers else self.answer


class TakeBackPipelineTests(unittest.TestCase):
    def test_a_clean_dictation_with_a_take_back_runs_as_a_fix(self) -> None:
        cleaner = _RecordingCleaner("Manda el reporte el martes.")
        pipeline = DictationPipeline(transcriber=None, cleaner=cleaner)

        result = pipeline.process_text("manda el reporte el lunes, borra eso, el martes")

        self.assertEqual(cleaner.modes, ["fix"])
        self.assertEqual(result.final_text, "Manda el reporte el martes.")

    def test_the_fix_guard_still_refuses_an_invented_word(self) -> None:
        cleaner = _RecordingCleaner("Manda el informe el martes.")
        pipeline = DictationPipeline(transcriber=None, cleaner=cleaner)

        with self.assertRaises(Exception) as caught:
            pipeline.process_text("manda el reporte el lunes, borra eso, el martes")

        self.assertEqual(getattr(caught.exception, "reason", None), "guard")

    def test_a_clean_dictation_without_one_keeps_the_conservative_path(self) -> None:
        cleaner = _RecordingCleaner("Manda el reporte el martes.")
        pipeline = DictationPipeline(transcriber=None, cleaner=cleaner)

        with self.assertRaises(Exception):
            # Deleting "el lunes" is refused when nothing was taken back.
            pipeline.process_text("manda el reporte el lunes el martes")
        self.assertEqual(cleaner.modes, ["clean"])

    def test_other_modes_are_never_switched(self) -> None:
        cleaner = _RecordingCleaner("Send the report on Tuesday.", mode="translate")
        pipeline = DictationPipeline(transcriber=None, cleaner=cleaner)

        pipeline.process_text("manda el reporte el lunes, borra eso, el martes")

        self.assertEqual(cleaner.modes, ["translate"])

    def test_the_literal_engine_is_never_switched(self) -> None:
        pipeline = DictationPipeline(transcriber=None, cleaner=LiteralCleaner())

        result = pipeline.process_text("el lunes, borra eso, el martes")

        self.assertEqual(result.final_text, "el lunes, borra eso, el martes")


class TakeBackFallbackTests(unittest.TestCase):
    def test_a_refused_fix_falls_back_to_the_ordinary_cleanup(self) -> None:
        """A fix that invents a word loses the fix, not the whole cleanup."""
        cleaner = _RecordingCleaner({
            "fix": "La reunión es el viernes con Pedro.",
            "clean": "La reunión es el lunes, perdón, el martes.",
        })
        pipeline = DictationPipeline(transcriber=None, cleaner=cleaner)

        result = pipeline.process_text("la reunión es el lunes perdón el martes")

        self.assertEqual(cleaner.modes, ["fix", "clean"])
        self.assertEqual(result.final_text, "La reunión es el lunes, perdón, el martes.")
