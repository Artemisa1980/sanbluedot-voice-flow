import unittest

from sanbluedot_voiceflow.errors import CleanupError
from sanbluedot_voiceflow.output_guard import guard_conservative_cleanup


class OutputGuardTests(unittest.TestCase):
    def test_allows_punctuation_and_unambiguous_filler_deletion(self) -> None:
        source = "Please um book Saturday"
        self.assertEqual(
            guard_conservative_cleanup(source, "Please book Saturday."),
            "Please book Saturday.",
        )

    def test_rejects_meaning_changing_deletion(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup(
                "do not send this message",
                "Send this message.",
            )

    def test_does_not_treat_an_all_caps_acronym_as_a_filler(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup("Visit UM today", "Visit today.")

    def test_rejects_new_or_reordered_words(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup("pay six dollars", "Pay seven dollars.")
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup("first second", "Second first.")

    def test_rejects_a_changed_url(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup(
                "Open https://example.com/report.",
                "Open https://example.com/admin.",
            )

    def test_rejects_new_command_flags_and_operators(self) -> None:
        unsafe_pairs = [
            ("Run rm rf in the terminal", "Run rm -rf in the terminal"),
            ("Use x y", "Use x/y"),
            ("Pay 1 2", "Pay 1+2"),
        ]

        for source, candidate in unsafe_pairs:
            with self.subTest(candidate=candidate), self.assertRaises(CleanupError):
                guard_conservative_cleanup(source, candidate)

    def test_rejects_removing_semantic_punctuation(self) -> None:
        unsafe_pairs = [
            ("Use x/y", "Use x y"),
            ("Version 1.2", "Version 1 2"),
            ("Run rm -rf", "Run rm rf"),
            ("Pay $5", "Pay 5"),
        ]

        for source, candidate in unsafe_pairs:
            with self.subTest(candidate=candidate), self.assertRaises(CleanupError):
                guard_conservative_cleanup(source, candidate)

    def test_still_allows_narrow_prose_punctuation(self) -> None:
        self.assertEqual(
            guard_conservative_cleanup("Hello world", "Hello, world!"),
            "Hello, world!",
        )

    def test_rejects_internal_punctuation_that_can_be_executable_syntax(self) -> None:
        unsafe_pairs = [
            ("echo safe rm file", "echo safe; rm file"),
            ("echo safe; rm file", "echo safe rm file"),
            ("echo; safe rm file", "echo safe; rm file"),
            ("let x int", "let x: int"),
            (
                "Open https://example.com echo safe",
                "Open https://example.com; echo safe",
            ),
        ]

        for source, candidate in unsafe_pairs:
            with self.subTest(candidate=candidate), self.assertRaises(CleanupError):
                guard_conservative_cleanup(source, candidate)


class RepeatedTerminalPunctuationTests(unittest.TestCase):
    """A run of terminal marks is presentation, not content.

    whisper.cpp commonly emits "..." and "?!". Treating every mark but the last as
    protected content made ordinary cleanup look like deletion, so the guard rejected it
    and the speaker silently received the unpunctuated transcript.
    """

    def test_an_ellipsis_may_be_reduced_to_one_mark(self) -> None:
        self.assertEqual(
            guard_conservative_cleanup("wait...", "Wait."), "Wait."
        )

    def test_a_mixed_run_may_be_reduced(self) -> None:
        self.assertEqual(
            guard_conservative_cleanup("really?!", "Really?"), "Really?"
        )

    def test_a_run_mid_sentence_is_still_allowed_to_go(self) -> None:
        self.assertEqual(
            guard_conservative_cleanup("wait... now go", "Wait, now go."),
            "Wait, now go.",
        )

    def test_a_word_is_still_never_deletable(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup("wait... now go", "Wait.")


if __name__ == "__main__":
    unittest.main()
