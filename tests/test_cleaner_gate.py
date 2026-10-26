import unittest

from scripts.cleaner_gate import (
    align,
    annotate,
    evaluate,
    punctuation_agreement,
    verdict,
    word_difference,
)


class AnnotationTests(unittest.TestCase):
    def test_a_mark_is_stored_on_the_word_it_follows(self) -> None:
        self.assertEqual(
            annotate("Hola, mundo."),
            [("hola", ","), ("mundo", ".")],
        )

    def test_a_closing_quote_does_not_hide_the_mark(self) -> None:
        self.assertEqual(annotate('dijo "vale".'), [("dijo", ""), ("vale", ".")])

    def test_an_unpunctuated_word_carries_the_empty_mark(self) -> None:
        self.assertEqual(annotate("hola mundo"), [("hola", ""), ("mundo", "")])


class AlignmentTests(unittest.TestCase):
    def test_a_dropped_word_does_not_desynchronise_the_tail(self) -> None:
        pairs = align(["el", "reporte", "de", "abril"], ["el", "reporte", "abril"])

        self.assertEqual(pairs, [(0, 0), (1, 1), (3, 2)])

    def test_nothing_aligns_between_unrelated_sequences(self) -> None:
        self.assertEqual(align(["uno"], ["dos"]), [])


class PunctuationAgreementTests(unittest.TestCase):
    def test_matching_punctuation_scores_a_perfect_f1(self) -> None:
        agreement = punctuation_agreement("Hola, mundo.", "Hola, mundo.")

        self.assertEqual(agreement.f1, 1.0)

    def test_missing_punctuation_costs_recall_not_precision(self) -> None:
        agreement = punctuation_agreement("Hola, mundo.", "Hola mundo")

        self.assertEqual(agreement.reference_total, 2)
        self.assertEqual(agreement.hypothesis_total, 0)
        self.assertEqual(agreement.recall, 0.0)

    def test_invented_punctuation_costs_precision(self) -> None:
        agreement = punctuation_agreement("Hola mundo", "Hola, mundo,")

        self.assertEqual(agreement.matched, 0)
        self.assertEqual(agreement.precision, 0.0)

    def test_a_mark_after_an_unrecovered_word_is_neither_credited_nor_charged(self) -> None:
        # "abril" was never recognised, so the comma the speaker wrote after it cannot
        # be attributed to cleanup either way.
        agreement = punctuation_agreement("el reporte de abril, listo", "el reporte de listo")

        self.assertEqual(agreement.matched, 0)
        self.assertEqual(agreement.reference_total, 0)
        self.assertEqual(agreement.hypothesis_total, 0)


class WordDifferenceTests(unittest.TestCase):
    def test_punctuation_only_changes_are_not_word_changes(self) -> None:
        self.assertEqual(word_difference("hola mundo", "Hola, mundo."), [])

    def test_removing_an_unambiguous_filler_is_permitted(self) -> None:
        self.assertEqual(word_difference("hola um mundo", "Hola, mundo."), [])

    def test_a_substituted_word_is_reported(self) -> None:
        self.assertIn("mundo", word_difference("hola mundo", "hola planeta"))


class FakeCleaner:
    name = "fake"

    def __init__(self, replies: dict[str, str]) -> None:
        self.replies = replies

    def clean(self, text: str, language_hint: str | None = None) -> str:
        del language_hint
        return self.replies.get(text, text)


class EvaluationTests(unittest.TestCase):
    def sample(self, identifier: int, reference: str, personalized: str) -> dict[str, object]:
        return {
            "id": identifier,
            "category": "all",
            "reference": reference,
            "personalized": personalized,
            "detected_language": "es",
        }

    def test_punctuation_recovered_by_cleanup_earns_a_pass(self) -> None:
        transcribed = [self.sample(1, "Hola, mundo.", "hola mundo")]
        cleaner = FakeCleaner({"hola mundo": "Hola, mundo."})

        report = evaluate(cleaner, transcribed)

        self.assertEqual(report["accepted"], 1)
        self.assertEqual(report["violations"], [])
        self.assertEqual(report["after"].f1, 1.0)
        self.assertEqual(verdict(report)[0], "PASS")

    def test_a_cleaner_that_changes_nothing_is_conditional_not_pass(self) -> None:
        transcribed = [self.sample(1, "Hola, mundo.", "Hola, mundo.")]

        report = evaluate(FakeCleaner({}), transcribed)

        self.assertEqual(report["changed"], 0)
        self.assertEqual(verdict(report)[0], "CONDITIONAL")

    def test_invented_words_are_refused_by_the_guard_and_counted(self) -> None:
        transcribed = [self.sample(1, "Hola, mundo.", "hola mundo")]
        cleaner = FakeCleaner({"hola mundo": "Hola, mundo entero."})

        report = evaluate(cleaner, transcribed)

        self.assertEqual(report["accepted"], 0)
        self.assertEqual(len(report["rejected"]), 1)
        self.assertEqual(report["violations"], [])
        self.assertEqual(verdict(report)[0], "FAIL")

    def test_punctuation_that_moves_away_from_the_reference_fails(self) -> None:
        transcribed = [self.sample(1, "Hola, mundo.", "Hola, mundo.")]
        cleaner = FakeCleaner({"Hola, mundo.": "Hola mundo,"})

        report = evaluate(cleaner, transcribed)

        self.assertLess(report["after"].f1, report["before"].f1)
        self.assertEqual(verdict(report)[0], "FAIL")

    def test_a_corpus_without_punctuation_is_refused_rather_than_scored(self) -> None:
        # The known blind spot, stated instead of hidden: with nothing to compare
        # against, invented marks would score the same as correct ones.
        transcribed = [self.sample(1, "Hola mundo", "Hola mundo")]
        cleaner = FakeCleaner({"Hola mundo": "Hola, mundo,"})

        report = evaluate(cleaner, transcribed)

        self.assertEqual(verdict(report)[0], "INVALID")


if __name__ == "__main__":
    unittest.main()


class InnerDotTests(unittest.TestCase):
    """D-100: a dot inside a token is not punctuation."""

    def test_inner_dots_carry_no_mark(self) -> None:
        from scripts.cleaner_gate import annotate

        self.assertEqual(annotate("version 3.5 listo"), [("version", ""), ("3", ""), ("5", ""), ("listo", "")])
        self.assertEqual(annotate("listo.")[-1], ("listo", "."))
