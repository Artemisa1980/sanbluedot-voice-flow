import json
import tempfile
import unittest
from pathlib import Path

from sanbluedot_voiceflow.memory import (
    Correction,
    CorrectionStore,
    apply_corrections,
    build_initial_prompt,
    load_vocabulary,
)


def pair(heard: str, intended: str) -> Correction:
    return Correction(heard=heard, intended=intended, confirmed_at="2026-08-29T00:00:00+00:00")


class VocabularyTests(unittest.TestCase):
    def test_reads_priority_order_and_skips_blanks_and_duplicates(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "vocabulary.local.txt"
            path.write_text(
                "sanblueᵈᵒᵗ\n\n# comentario\nUTEL\nutel\n  Gim  \n",
                encoding="utf-8",
            )

            self.assertEqual(load_vocabulary(path), ["sanblueᵈᵒᵗ", "UTEL", "Gim"])

    def test_missing_file_is_not_an_error(self) -> None:
        self.assertEqual(load_vocabulary(Path("/nonexistent/vocabulary.txt")), [])

    def test_unreadable_vocabulary_is_quarantined(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "vocabulary.local.txt"
            path.write_bytes(b"UTEL\n\xff")

            self.assertEqual(load_vocabulary(path), [])
            self.assertFalse(path.exists())
            self.assertEqual(
                len([f for f in Path(temp_dir).iterdir() if ".corrupt-" in f.name]),
                1,
            )

    def test_prompt_fills_from_the_top_and_respects_the_budget(self) -> None:
        terms = ["IESS", "BIESS", "CONSAR", "SIEFORE"]

        self.assertEqual(build_initial_prompt(terms, char_budget=12), "IESS, BIESS")
        self.assertEqual(build_initial_prompt(terms, char_budget=3), "")

    def test_real_vocabulary_prompt_stays_inside_the_engine_cap(self) -> None:
        terms = [f"term{index}" for index in range(500)]

        prompt = build_initial_prompt(terms)

        self.assertLessEqual(len(prompt), 600)

    def test_a_full_store_leaves_no_room_for_appended_terms(self) -> None:
        """The budget, not the caller, decides what reaches whisper.

        A fixture of two or three terms cannot show this: it leaves 580 characters free,
        so anything appended survives and a dead feature reads as a working one. The
        real store carries 226 terms.
        """
        terms = [f"term{index:03d}" for index in range(226)]

        prompt = build_initial_prompt(terms)

        self.assertLessEqual(len(prompt), 600)
        self.assertNotIn(f"term{225:03d}", prompt)


class ApplyCorrectionsTests(unittest.TestCase):
    def test_replaces_a_whole_word_only(self) -> None:
        corrections = [pair("meditation", "dictation")]

        self.assertEqual(
            apply_corrections("a short English meditation", corrections),
            "a short English dictation",
        )

    def test_leaves_unrelated_text_untouched(self) -> None:
        # Gate 3: a pair fixes its target without rewriting anything else.
        corrections = [pair("IRA", "IRA")]

        self.assertEqual(apply_corrections("mira la lira", corrections), "mira la lira")

    def test_does_not_rewrite_a_fragment_inside_a_longer_word(self) -> None:
        corrections = [pair("SAT", "SAT")]

        self.assertEqual(apply_corrections("satisfecho", corrections), "satisfecho")

    def test_longest_phrase_wins(self) -> None:
        corrections = [pair("how", "who"), pair("how thorn", "Hawthorne")]

        self.assertEqual(
            apply_corrections("el efecto how thorn", corrections),
            "el efecto Hawthorne",
        )

    def test_preserves_the_casing_of_the_matched_text(self) -> None:
        corrections = [pair("meditation", "dictation")]

        self.assertEqual(
            apply_corrections("Meditation and MEDITATION", corrections),
            "Dictation and DICTATION",
        )

    def test_matches_accented_terms(self) -> None:
        corrections = [pair("jerarquia", "jerarquía")]

        self.assertEqual(
            apply_corrections("la jerarquia formal", corrections),
            "la jerarquía formal",
        )

    def test_handles_a_term_ending_in_a_non_word_character(self) -> None:
        corrections = [pair("san blue dot", "sanblueᵈᵒᵗ")]

        self.assertEqual(
            apply_corrections("el proyecto san blue dot", corrections),
            "el proyecto sanblueᵈᵒᵗ",
        )

    def test_no_corrections_returns_the_text_unchanged(self) -> None:
        self.assertEqual(apply_corrections("texto intacto", []), "texto intacto")


class ConfirmedPairCollisionTests(unittest.TestCase):
    """The pairs actually confirmed for Gate 3, against text that could collide.

    The Gate 3 control corpus could not detect collateral damage, because none of the
    pairs' heard strings occur in it. These sentences do contain them, inside longer
    words, so a matching bug fails here instead of silently in real dictation.
    """

    CONFIRMED = [
        pair("ies", "IESS"),
        pair("srai 1", "SRI"),
        pair("sun blue dog", "sanblueᵈᵒᵗ"),
        pair("bes", "BIESS"),
        pair("jin", "Gim"),
        pair("meditation", "dictation"),
        pair("voice flow", "VoiceFlow"),
    ]

    def assert_unchanged(self, text: str) -> None:
        self.assertEqual(apply_corrections(text, self.CONFIRMED), text)

    def test_ies_inside_longer_words_is_untouched(self) -> None:
        self.assert_unchanged("Las especies y las series de la empresa")
        self.assert_unchanged("si vieses el informe de clientes")

    def test_bes_inside_longer_words_is_untouched(self) -> None:
        self.assert_unchanged("bebes café y le das besos al perro")

    def test_jin_inside_longer_words_is_untouched(self) -> None:
        self.assert_unchanged("el jinete llegó con la jineta")

    def test_ordinary_sentences_survive_every_pair(self) -> None:
        self.assert_unchanged("Ayer llovió toda la tarde y no pude salir de casa")
        self.assert_unchanged("We should discuss this again before making a decision")
        self.assert_unchanged("Mi hermana llega el domingo por la mañana en avión")

    def test_the_pairs_still_fire_on_their_own_targets(self) -> None:
        self.assertEqual(
            apply_corrections("aporté al ies y al bes este mes", self.CONFIRMED),
            "aporté al IESS y al BIESS este mes",
        )
        self.assertEqual(
            apply_corrections("el proyecto sun blue dog con jin", self.CONFIRMED),
            "el proyecto sanblueᵈᵒᵗ con Gim",
        )


class DurabilityTests(unittest.TestCase):
    def test_unsupported_schema_is_quarantined(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "corrections.local.json"
            path.write_text(
                json.dumps({"schema_version": 999, "corrections": []}),
                encoding="utf-8",
            )

            self.assertEqual(CorrectionStore(path).load(), [])
            self.assertFalse(path.exists())

    def test_legacy_unversioned_schema_is_read_as_version_one(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "corrections.local.json"
            path.write_text(
                json.dumps({"corrections": [
                    {"heard": "ies", "intended": "IESS", "confirmed_at": ""}
                ]}),
                encoding="utf-8",
            )

            self.assertEqual([item.heard for item in CorrectionStore(path).load()], ["ies"])

    def test_a_truncated_store_is_quarantined_instead_of_blocking_dictation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "corrections.local.json"
            path.write_text('{"schema_version": 1, "correcti', encoding="utf-8")

            self.assertEqual(CorrectionStore(path).load(), [])
            self.assertFalse(path.exists())
            self.assertEqual(
                len([f for f in Path(temp_dir).iterdir() if ".corrupt-" in f.name]), 1
            )

    def test_a_write_leaves_no_partial_file_behind(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            store = CorrectionStore(Path(temp_dir) / "corrections.local.json")
            store.add("ies", "IESS")

            names = sorted(f.name for f in Path(temp_dir).iterdir())

            self.assertIn("corrections.local.json", names)
            self.assertFalse(any(name.endswith(".tmp") for name in names))
            self.assertEqual(json.loads(store.path.read_text(encoding="utf-8"))
                             ["schema_version"], 1)

    def test_valid_json_with_the_wrong_shape_is_quarantined(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "corrections.local.json"
            path.write_text("[]", encoding="utf-8")

            self.assertEqual(CorrectionStore(path).load(), [])
            self.assertFalse(path.exists())
            self.assertEqual(
                len([f for f in Path(temp_dir).iterdir() if ".corrupt-" in f.name]),
                1,
            )

    def test_entries_missing_a_side_are_ignored_rather_than_applied(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "c.json"
            path.write_text(
                json.dumps({"schema_version": 1, "corrections": [
                    {"heard": "ies", "intended": "IESS"},
                    {"heard": "", "intended": "roto"},
                    {"heard": "otro"},
                    "no soy un objeto",
                ]}),
                encoding="utf-8",
            )

            self.assertEqual([c.heard for c in CorrectionStore(path).load()], ["ies"])


class CascadeTests(unittest.TestCase):
    def test_one_pairs_output_is_never_rewritten_by_another_pair(self) -> None:
        corrections = [pair("sun blue dog", "jin"), pair("jin", "Gim")]

        self.assertEqual(
            apply_corrections("el proyecto sun blue dog", corrections),
            "el proyecto jin",
        )

    def test_each_pair_still_fires_on_its_own_trigger(self) -> None:
        corrections = [pair("sun blue dog", "jin"), pair("jin", "Gim")]

        self.assertEqual(apply_corrections("hola jin", corrections), "hola Gim")


class CorrectionStoreTests(unittest.TestCase):
    def test_add_list_and_delete_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            store = CorrectionStore(Path(temp_dir) / "nested" / "corrections.local.json")

            store.add("meditation", "dictation")
            store.add("how thorn", "Hawthorne")

            self.assertEqual(
                [(item.heard, item.intended) for item in store.load()],
                [("meditation", "dictation"), ("how thorn", "Hawthorne")],
            )
            self.assertTrue(store.remove("meditation"))
            self.assertEqual([item.heard for item in store.load()], ["how thorn"])
            self.assertFalse(store.remove("meditation"))

    def test_re_adding_a_pair_replaces_it(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            store = CorrectionStore(Path(temp_dir) / "corrections.local.json")

            store.add("IESS", "ISS")
            store.add("iess", "IESS")

            self.assertEqual(
                [(item.heard, item.intended) for item in store.load()],
                [("iess", "IESS")],
            )

    def test_an_incomplete_pair_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            store = CorrectionStore(Path(temp_dir) / "corrections.local.json")

            with self.assertRaises(ValueError):
                store.add("  ", "dictation")

    def test_missing_file_reads_as_empty(self) -> None:
        self.assertEqual(CorrectionStore(Path("/nonexistent/c.json")).load(), [])


if __name__ == "__main__":
    unittest.main()
