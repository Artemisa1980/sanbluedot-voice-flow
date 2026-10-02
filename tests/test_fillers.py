import unittest

from sanbluedot_voiceflow.cleaners.fillers import remove_fillers
from sanbluedot_voiceflow.pipeline import DictationPipeline


class RemoveFillersTests(unittest.TestCase):
    def test_fillers_go_with_their_commas_and_the_sentence_keeps_its_capital(self) -> None:
        cases = {
            "Eh, bueno, la reunión es el viernes.": "Bueno, la reunión es el viernes.",
            "La reunión, eh, es el viernes.": "La reunión es el viernes.",
            "I need um the report by Friday.": "I need the report by Friday.",
            "Uh. Let's start.": "Let's start.",
            "Listo eh.": "Listo.",
        }
        for heard, expected in cases.items():
            with self.subTest(heard=heard):
                self.assertEqual(remove_fillers(heard), expected)

    def test_text_without_a_filler_and_an_all_caps_acronym_are_left_alone(self) -> None:
        for text in ("Sin muletillas aquí.", "The UM acronym stays.", "Ehrlich ruled, Uhura spoke."):
            with self.subTest(text=text):
                self.assertEqual(remove_fillers(text), text)


class SpyCleaner:
    """A model-backed cleaner that records whether it was asked at all."""

    name = "apple"
    mode = "clean"

    def __init__(self, fix_result: str | None = None) -> None:
        self.calls: list[str] = []
        self.fix_result = fix_result

    def clean(self, text: str, language_hint: str | None = None, mode: str | None = None) -> str:
        self.calls.append(mode or self.mode)
        if mode == "fix" and self.fix_result is not None:
            return self.fix_result
        return text


class NoModelCleanTests(unittest.TestCase):
    def test_an_ordinary_dictation_asks_no_model(self) -> None:
        cleaner = SpyCleaner()
        pipeline = DictationPipeline(None, cleaner, model_only_for_take_back=True)

        result = pipeline.process_text("Eh, mañana enviamos el informe.")

        self.assertEqual(cleaner.calls, [])
        self.assertEqual(result.final_text, "Mañana enviamos el informe.")
        self.assertEqual(result.cleaner, "fillers")

    def test_a_take_back_still_goes_to_the_model(self) -> None:
        cleaner = SpyCleaner(fix_result="Nos vemos a las cinco.")
        pipeline = DictationPipeline(None, cleaner, model_only_for_take_back=True)

        result = pipeline.process_text("Nos vemos a las cuatro, no, mejor no, a las cinco.")

        self.assertEqual(cleaner.calls, ["fix"])
        self.assertEqual(result.final_text, "Nos vemos a las cinco.")
        self.assertEqual(result.cleaner, "apple")

    def test_a_refused_fix_falls_back_to_the_rule_not_to_a_second_model_call(self) -> None:
        cleaner = SpyCleaner(fix_result="Nos vemos mañana a las cinco.")
        pipeline = DictationPipeline(None, cleaner, model_only_for_take_back=True)

        result = pipeline.process_text("Eh, nos vemos a las cuatro, no, mejor no, a las cinco.")

        self.assertEqual(cleaner.calls, ["fix"])
        self.assertEqual(result.final_text, "Nos vemos a las cuatro, no, mejor no, a las cinco.")

    def test_without_the_flag_the_model_cleans_as_before(self) -> None:
        cleaner = SpyCleaner()
        DictationPipeline(None, cleaner).process_text("Mañana enviamos el informe.")
        self.assertEqual(cleaner.calls, ["clean"])


if __name__ == "__main__":
    unittest.main()
