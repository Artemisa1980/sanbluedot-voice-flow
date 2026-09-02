import unittest

from scripts.phase2_report import build_report, percentile, word_error_rate


class Phase2ReportTests(unittest.TestCase):
    def test_word_error_rate_ignores_case_and_punctuation(self) -> None:
        self.assertEqual(word_error_rate("Hola, TEST.", "hola test"), 0.0)
        self.assertEqual(word_error_rate("one two", "one three"), 0.5)

    def test_percentile_interpolates_ordered_values(self) -> None:
        self.assertEqual(percentile([1.0, 2.0, 3.0], 0.5), 2.0)
        self.assertAlmostEqual(percentile([1.0, 2.0], 0.95), 1.95)

    def test_report_uses_exactly_twenty_ordered_results(self) -> None:
        corpus = [
            {
                "id": sequence,
                "target_app": "Notes",
                "category": "English",
                "reference": f"sample {sequence}",
            }
            for sequence in range(1, 21)
        ]
        results = [
            {
                "sequence": sequence,
                "latency_seconds": float(sequence),
                "raw_text": f"sample {sequence}",
                "final_text": f"Sample {sequence}.",
                "used_fallback": False,
            }
            for sequence in range(1, 21)
        ]

        report = build_report(corpus, results, {"Notes"})

        self.assertIn("Completed recordings: 20/20", report)
        self.assertIn("Notes: confirmed", report)
        self.assertIn("Mean cleaned WER: 0.0%", report)
        self.assertIn("Mean personalized WER: 0.0%", report)
        self.assertIn("Safe fallbacks: 0", report)


    def test_a_corpus_out_of_order_is_refused(self) -> None:
        corpus = [{"id": 2, "target_app": "Notes", "category": "English",
                   "reference": "sample"}] * 20
        results = [{"sequence": i, "latency_seconds": 1.0, "raw_text": "sample",
                    "final_text": "sample", "used_fallback": False}
                   for i in range(1, 21)]

        with self.assertRaises(ValueError):
            build_report(corpus, results, set())

    def test_a_result_out_of_order_is_refused(self) -> None:
        corpus = [{"id": i, "target_app": "Notes", "category": "English",
                   "reference": "sample"} for i in range(1, 21)]
        results = [{"sequence": 99, "latency_seconds": 1.0, "raw_text": "sample",
                    "final_text": "sample", "used_fallback": False}] * 20

        with self.assertRaises(ValueError):
            build_report(corpus, results, set())

    def test_a_short_run_is_refused_rather_than_reported(self) -> None:
        corpus = [{"id": i, "target_app": "Notes", "category": "English",
                   "reference": "sample"} for i in range(1, 21)]

        with self.assertRaises(ValueError):
            build_report(corpus, [], set())


if __name__ == "__main__":
    unittest.main()
