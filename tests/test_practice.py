import json
import os
import shutil
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from sanbluedot_voiceflow.practice import (
    MAX_TAKE_SECONDS,
    _is_formatting,
    PracticeStore,
    compare,
    recovered_words,
    sweep_orphan_takes,
)


def missed(reference: str, heard: str) -> list[tuple[str, str]]:
    return [(d.read, d.heard) for d in compare(reference, heard) if d.kind == "missed"]


def formatting(reference: str, heard: str) -> list[tuple[str, str]]:
    return [(d.read, d.heard) for d in compare(reference, heard) if d.kind == "formatting"]


class CompareTests(unittest.TestCase):
    def test_a_perfect_read_has_no_differences(self) -> None:
        self.assertEqual(compare("The tests run without changes", "the tests run without changes"), [])

    def test_punctuation_and_case_are_not_differences(self) -> None:
        self.assertEqual(compare("¿Todo bien, entonces?", "todo bien entonces"), [])

    def test_a_dropped_written_accent_is_formatting_not_a_missed_word(self) -> None:
        self.assertEqual(missed("buenos días", "buenos dias"), [])
        self.assertEqual(formatting("buenos días", "buenos dias"), [("días", "dias")])

    def test_the_tilde_still_counts_because_it_changes_the_word(self) -> None:
        self.assertEqual(missed("hace un año", "hace un ano"), [("año", "ano")])

    def test_a_dropped_ending_is_a_missed_word(self) -> None:
        self.assertEqual(missed("the tests run", "the test run"), [("tests", "test")])

    def test_a_spoken_number_written_as_a_numeral_is_formatting(self) -> None:
        self.assertEqual(missed("send it before six", "send it before 6"), [])
        self.assertEqual(formatting("send it before six", "send it before 6"), [("six", "6")])

    def test_a_multiword_number_is_formatting(self) -> None:
        self.assertEqual(missed("it starts at nine thirty", "it starts at 9 30"), [])

    def test_a_spanish_number_is_formatting(self) -> None:
        self.assertEqual(formatting("hay cinco casos", "hay 5 casos"), [("cinco", "5")])
        self.assertEqual(formatting("hay dieciséis casos", "hay 16 casos"),
                         [("dieciséis", "16")])
        self.assertEqual(missed("hay treinta y un casos", "hay 31 casos"), [])
        self.assertEqual(missed("hay doscientos casos", "hay 200 casos"), [])

    def test_lost_spacing_is_formatting_not_a_missed_word(self) -> None:
        self.assertEqual(missed("go to open example", "go to openexample"), [])

    def test_a_real_vowel_swap_is_missed_not_formatting(self) -> None:
        self.assertEqual(missed("time for lunch", "time for launch"), [("lunch", "launch")])

    def test_a_dropped_word_is_reported_with_an_empty_side(self) -> None:
        self.assertEqual(missed("she is going home", "she going home"), [("is", "")])


class CompoundNumberTests(unittest.TestCase):
    def test_a_summed_compound_number_is_formatting(self) -> None:
        self.assertEqual(missed("it costs forty two dollars", "it costs 42 dollars"), [])
        self.assertEqual(missed("page twenty five", "page 25"), [])

    def test_a_spoken_time_stays_formatting_too(self) -> None:
        self.assertEqual(missed("it starts at nine thirty", "it starts at 9 30"), [])

    def test_hundreds_are_summed_not_concatenated(self) -> None:
        self.assertEqual(missed("three hundred pesos", "300 pesos"), [])
        self.assertEqual(missed("one hundred thousand pesos", "100000 pesos"), [])
        self.assertEqual(missed("two million cases", "2000000 cases"), [])

    def test_spoken_oh_in_a_number_is_formatting(self) -> None:
        self.assertEqual(missed("room one oh five", "room 105"), [])

    def test_a_wrong_number_is_still_a_missed_word(self) -> None:
        self.assertEqual(missed("page twenty five", "page 26"), [("twenty five", "26")])


class SymbolFormattingTests(unittest.TestCase):
    """A symbol the engine writes where the speaker said a word is formatting.

    Found by the Gate 6 acceptance session on 2026-09-02: "twelve percent" written as
    `12%` and "cuarenta y dos mil dólares" written as `$42,000` were both reported as
    missed words, telling the speaker they had mispronounced something they said
    correctly. That is the false signal R8 exists to prevent.
    """

    def test_a_percent_sign_is_the_word_percent(self) -> None:
        self.assertEqual(
            missed(
                "The forecast assumes a twelve percent margin.",
                "The forecast assumes a 12% margin.",
            ),
            [],
        )

    def test_spanish_por_ciento_is_the_same_symbol(self) -> None:
        self.assertEqual(missed("un doce por ciento de margen", "un 12% de margen"), [])

    def test_a_currency_symbol_matches_the_spoken_word(self) -> None:
        self.assertEqual(
            missed(
                "el invoice de cuarenta y dos mil dólares",
                "el invoice de $42,000",
            ),
            [],
        )
        self.assertEqual(missed("a forty two thousand dollar invoice", "a $42,000 invoice"), [])

    def test_a_dropped_currency_word_is_still_a_missed_word(self) -> None:
        # The engine wrote the amount and no currency at all. That is not formatting:
        # the word the speaker said is simply absent.
        self.assertEqual(
            missed("cuarenta y dos mil dólares", "42000"),
            [("cuarenta y dos mil dólares", "42000")],
        )

    def test_a_dropped_percent_is_still_a_missed_word(self) -> None:
        # The aligner reports the whole differing span, so the number comes with it.
        self.assertEqual(
            missed("a twelve percent margin", "a 12 margin"),
            [("twelve percent", "12")],
        )

    def test_two_amounts_cannot_swap_their_currencies(self) -> None:
        # Found by the 2026-09-02 gate. Markers were compared as an unordered set and
        # the amounts were summed across the boundary, so 50+30 matched 30+50 and a
        # genuinely different sentence was reported as formatting — the one thing R8
        # says the report must never do.
        # The aligner reports the two swapped amounts as two differences, which is the
        # honest answer; what matters is that neither is called formatting.
        self.assertEqual(
            missed(
                "cincuenta dólares y treinta euros",
                "treinta dólares y cincuenta euros",
            ),
            [("cincuenta", "treinta"), ("treinta", "cincuenta")],
        )
        # And the whole span, which is what `_is_formatting` sees when the aligner
        # cannot split it, is not formatting either.
        self.assertFalse(
            _is_formatting(
                ["cincuenta", "dólares", "y", "treinta", "euros"],
                ["treinta", "dólares", "y", "cincuenta", "euros"],
            )
        )

    def test_two_different_currencies_do_not_match(self) -> None:
        self.assertEqual(
            missed("cuarenta y dos mil dólares", "€42,000"),
            [("cuarenta y dos mil dólares", "euros 42 000")],
        )


class OrphanTakeTests(unittest.TestCase):
    """A reserved recording no session claims is deleted, not left on disk.

    Found on 2026-09-02: a closed terminal left `ffmpeg` holding the microphone for
    fourteen minutes. The audio it wrote was never indexed, so nothing could list or
    delete it, which R7 does not allow.
    """

    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.directory, True)

    def _take(self, name: str, age_seconds: float = 0.0) -> Path:
        path = self.directory / name
        path.write_bytes(b"\0" * 100)
        if age_seconds:
            stamp = time.time() - age_seconds
            os.utime(path, (stamp, stamp))
        return path

    def test_a_stranded_take_is_removed(self) -> None:
        stranded = self._take("001.wav", age_seconds=MAX_TAKE_SECONDS + 60)
        removed = sweep_orphan_takes(self.directory, indexed=set())
        self.assertEqual(removed, [stranded])
        self.assertFalse(stranded.exists())

    def test_a_take_still_being_recorded_is_left_alone(self) -> None:
        # The dangerous case, found by the 2026-09-02 gate: a second `vf practice`
        # started while the first is still recording sees the first run's reserved
        # file, which is not in the index yet either. Deleting it destroys a recording
        # in progress and the speaker is told the microphone has no permission.
        # `ffmpeg` writes continuously and caps itself at MAX_TAKE_SECONDS, so nothing
        # younger than that can be assumed dead.
        live = self._take("001.wav")
        self.assertEqual(sweep_orphan_takes(self.directory, indexed=set()), [])
        self.assertTrue(live.exists())

    def test_a_reserved_but_silent_take_is_swept_once_it_is_old(self) -> None:
        # Reserved by name, ffmpeg never started, the run died. Nothing can list or
        # delete it, so it goes — but only after it is too old to be live.
        reserved = self.directory / "003.wav"
        reserved.touch()
        self.assertEqual(sweep_orphan_takes(self.directory, indexed=set()), [])
        stamp = time.time() - (MAX_TAKE_SECONDS + 1)
        os.utime(reserved, (stamp, stamp))
        self.assertEqual(sweep_orphan_takes(self.directory, indexed=set()), [reserved])

    def test_an_indexed_take_is_kept(self) -> None:
        kept = self._take("002.wav", age_seconds=MAX_TAKE_SECONDS + 60)
        self.assertEqual(sweep_orphan_takes(self.directory, indexed={2}), [])
        self.assertTrue(kept.exists())

    def test_other_files_are_never_touched(self) -> None:
        index = self.directory / "sessions.local.json"
        index.write_text("{}", encoding="utf-8")
        note = self.directory / "notes.wav"
        note.write_bytes(b"\0" * 100)
        os.utime(note, (0, 0))
        sweep_orphan_takes(self.directory, indexed=set())
        self.assertTrue(index.exists())
        self.assertTrue(note.exists())

    def test_a_missing_directory_is_not_an_error(self) -> None:
        self.assertEqual(sweep_orphan_takes(self.directory / "gone", set()), [])

    def test_the_store_reads_and_sweeps_under_one_lock(self) -> None:
        # Reading the index and sweeping as two steps let a second run act on a view
        # that had already gone stale.
        store = PracticeStore(self.directory)
        stranded = self._take("001.wav", age_seconds=MAX_TAKE_SECONDS + 60)
        self.assertEqual(store.sweep_orphans(), [stranded])
        self.assertFalse(stranded.exists())

    def test_a_take_is_capped_so_it_cannot_hold_the_microphone(self) -> None:
        self.assertLessEqual(MAX_TAKE_SECONDS, 600)
        self.assertGreater(MAX_TAKE_SECONDS, 0)


class RecoveredWordsTests(unittest.TestCase):
    def test_a_clean_read_recovers_every_word(self) -> None:
        self.assertEqual(recovered_words("the tests run", "the tests run"), 3)

    def test_a_hallucinated_take_recovers_nothing(self) -> None:
        # Near-silence with a vocabulary prompt loaded produced exactly this.
        self.assertEqual(
            recovered_words("The tests run without changes", "in dubio pro operario"), 0
        )

    def test_a_partial_read_recovers_the_matching_words(self) -> None:
        self.assertEqual(recovered_words("the tests run", "the test run"), 2)

    def test_formatting_only_take_is_not_rejected(self) -> None:
        self.assertEqual(recovered_words("forty two", "42"), 2)
        self.assertEqual(recovered_words("días", "dias"), 1)


class PracticeStoreTests(unittest.TestCase):
    @staticmethod
    def stored_session(audio_file: str = "001.wav") -> dict[str, object]:
        return {
            "id": 1,
            "recorded_at": "2026-08-29T00:00:00+00:00",
            "reference": "one",
            "heard": "one",
            "audio_file": audio_file,
            "missed": [],
        }

    def test_sessions_are_added_listed_and_deleted_with_their_audio(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            store = PracticeStore(Path(temp_dir) / "practice")
            audio = store.next_audio_path()
            audio.write_bytes(b"x" * 100)

            session = store.add("the tests run", "the test run", audio)

            self.assertEqual(session["id"], 1)
            self.assertEqual(session["missed"], [{"read": "tests", "heard": "test"}])
            self.assertEqual(len(store.load()), 1)

            self.assertTrue(store.remove(1))
            self.assertEqual(store.load(), [])
            self.assertFalse(audio.exists())
            self.assertFalse(store.remove(1))

    def test_numbering_continues_after_the_existing_sessions(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            store = PracticeStore(Path(temp_dir) / "practice")
            first = store.next_audio_path()
            first.write_bytes(b"x")
            store.add("uno", "uno", first)

            self.assertEqual(store.next_audio_path().name, "002.wav")

    def test_a_deletion_never_makes_the_next_take_overwrite_a_kept_one(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            store = PracticeStore(Path(temp_dir) / "practice")
            for index in range(3):
                audio = store.next_audio_path()
                audio.write_bytes(b"x")
                store.add(f"ref {index}", f"ref {index}", audio)
            store.remove(2)

            following = store.next_audio_path()

            self.assertEqual(following.name, "004.wav")
            self.assertTrue(following.exists())
            self.assertEqual(following.stat().st_size, 0)
            self.assertTrue((store.directory / "003.wav").exists())

    def test_two_unfinished_takes_reserve_distinct_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            store = PracticeStore(Path(temp_dir) / "practice")

            first = store.next_audio_path()
            second = store.next_audio_path()

            self.assertEqual((first.name, second.name), ("001.wav", "002.wav"))

    def test_valid_json_with_the_wrong_shape_is_quarantined(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            directory = Path(temp_dir) / "practice"
            directory.mkdir()
            index = directory / "sessions.local.json"
            index.write_text("[]", encoding="utf-8")

            self.assertEqual(PracticeStore(directory).load(), [])
            self.assertFalse(index.exists())

    def test_unsupported_schema_is_quarantined(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            directory = Path(temp_dir) / "practice"
            directory.mkdir()
            index = directory / "sessions.local.json"
            index.write_text(
                json.dumps({"schema_version": 2, "sessions": []}),
                encoding="utf-8",
            )

            self.assertEqual(PracticeStore(directory).load(), [])
            self.assertFalse(index.exists())

    def test_unsafe_audio_path_is_quarantined_and_never_deleted(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            directory = root / "practice"
            directory.mkdir()
            victim = root / "victim.wav"
            victim.write_bytes(b"voice")
            index = directory / "sessions.local.json"
            index.write_text(
                json.dumps({
                    "schema_version": 1,
                    "sessions": [self.stored_session("../victim.wav")],
                }),
                encoding="utf-8",
            )

            store = PracticeStore(directory)
            self.assertEqual(store.load(), [])
            self.assertFalse(store.remove(1))
            self.assertTrue(victim.exists())
            self.assertFalse(index.exists())

    def test_failed_index_write_restores_the_recording(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            store = PracticeStore(Path(temp_dir) / "practice")
            audio = store.next_audio_path()
            audio.write_bytes(b"voice")
            store.add("one", "one", audio)

            with patch.object(store, "_write", side_effect=OSError("disk full")):
                with self.assertRaises(OSError):
                    store.remove(1)

            self.assertTrue(audio.exists())
            self.assertEqual([item["id"] for item in store.load()], [1])
            self.assertEqual(
                list(store.directory.glob("*.pending-delete")),
                [],
            )

    def test_a_missing_index_reads_as_empty(self) -> None:
        self.assertEqual(PracticeStore(Path("/nonexistent/practice")).load(), [])


if __name__ == "__main__":
    unittest.main()
