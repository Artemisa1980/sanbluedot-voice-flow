import json
import unittest

from sanbluedot_voiceflow.cleaners.prompt import (
    CONSERVATIVE_SYSTEM_PROMPT,
    FIX_SYSTEM_PROMPT,
)
from sanbluedot_voiceflow.errors import CleanupError
from sanbluedot_voiceflow.output_guard import (
    guard_conservative_cleanup,
    guard_fix_cleanup,
)


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



class SpanishFillerTests(unittest.TestCase):
    """The filler list was English only, so Spanish speech paid for it.

    Every cleaner that removed the Spanish `eh` had its whole cleanup refused, and the
    speaker received the raw transcript instead. Observed against Apple's on-device model
    on 2026-09-18.
    """

    def test_removing_the_spanish_eh_is_accepted(self) -> None:
        source = "eh bueno el reporte va el jueves"
        candidate = "Bueno, el reporte va el jueves."

        self.assertEqual(guard_conservative_cleanup(source, candidate), candidate)

    def test_words_that_can_be_content_are_still_protected(self) -> None:
        """`este` and `pues` carry meaning in ordinary Spanish and stay content."""
        for word in ("este", "pues"):
            with self.subTest(word=word):
                with self.assertRaises(CleanupError):
                    guard_conservative_cleanup(f"dame {word} reporte", "dame reporte")

    def test_an_acronym_is_not_a_filler(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup("el informe EH del banco", "el informe del banco")

if __name__ == "__main__":
    unittest.main()


class SpanishAccentTests(unittest.TestCase):
    """whisper.cpp writes Spanish without its written accents.

    A cleaner that puts them back was refused as having invented words, so Spanish
    cleanup was rejected on the ordinary case. Only the acute accent is folded for the
    comparison: `ñ` and `ü` are letters, not accents, and `ano` against `año` is a change
    of word.
    """

    def test_a_restored_accent_is_accepted(self) -> None:
        source = "la reunion es el miercoles y el informe esta listo"
        candidate = "La reunión es el miércoles y el informe está listo."

        self.assertEqual(guard_conservative_cleanup(source, candidate), candidate)

    def test_an_n_with_a_tilde_is_a_different_word(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup("el ano pasado", "el año pasado")

    def test_a_dieresis_is_a_different_word(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup("el pinguino", "el pingüino")

    def test_a_substitution_is_still_refused(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup("manda el reporte", "manda el informe")

    def test_an_accent_removed_is_accepted_too(self) -> None:
        """The fold is symmetric: the guard judges words, not orthography."""
        source = "la reunión es el miércoles"
        candidate = "La reunion es el miercoles."

        self.assertEqual(guard_conservative_cleanup(source, candidate), candidate)


class TypographicMarkTests(unittest.TestCase):
    """Marks a cleaner writes as typography, not as words (D-59, D-28)."""

    def test_a_typographic_apostrophe_is_the_same_word(self) -> None:
        candidate = "Don’t send it."
        self.assertEqual(guard_conservative_cleanup("don't send it", candidate), candidate)

    def test_the_apostrophe_does_not_hide_a_changed_word(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup("don't send it", "Won’t send it.")

    def test_opening_question_and_exclamation_marks_are_accepted(self) -> None:
        source = "como estas que bien"
        candidate = "¿Cómo estás? ¡Qué bien!"
        self.assertEqual(guard_conservative_cleanup(source, candidate), candidate)

    def test_an_opening_mark_does_not_hide_a_new_word(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup("como estas", "¿Cómo estás tú?")

    def test_a_detached_opening_mark_is_still_content(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup("como estas", "¿ cómo estás")

    def test_spanish_angle_quotes_are_accepted(self) -> None:
        source = "dijo hola mundo"
        candidate = "Dijo «hola mundo»."
        self.assertEqual(guard_conservative_cleanup(source, candidate), candidate)

    def test_opening_question_mark_after_parenthesis(self) -> None:
        source = "como estas seguro"
        candidate = "¿Cómo estás? (¿seguro?)."
        self.assertEqual(guard_conservative_cleanup(source, candidate), candidate)

    def test_diacritical_monosyllable_mutation_is_rejected(self) -> None:
        with self.assertRaises(CleanupError):
            guard_conservative_cleanup("si lo apruebo", "Sí, lo apruebo.")


class CleanupPromptTests(unittest.TestCase):
    def test_every_example_in_the_cleanup_prompt_passes_this_guard(self) -> None:
        """The prompt shows the model what to return, and this guard judges it.

        An example the guard refuses teaches the one output that is always discarded:
        "Friday, no, actually Saturday" became "Saturday", and every dictation with a
        self-correction lost its whole cleanup, punctuation included.
        """
        lines = CONSERVATIVE_SYSTEM_PROMPT.splitlines()
        sources = [
            line.removeprefix("Example input: ")
            for line in lines
            if line.startswith("Example input: ")
        ]
        candidates = [
            json.loads(line.removeprefix("Example output: "))["cleaned_text"]
            for line in lines
            if line.startswith("Example output: ")
        ]

        self.assertTrue(sources)
        self.assertEqual(len(sources), len(candidates))
        for source, candidate in zip(sources, candidates):
            with self.subTest(source=source):
                self.assertEqual(guard_conservative_cleanup(source, candidate), candidate)


def _prompt_examples(prompt: str) -> list[tuple[str, str]]:
    lines = prompt.splitlines()
    sources = [
        line.removeprefix("Example input: ")
        for line in lines
        if line.startswith("Example input: ")
    ]
    candidates = [
        json.loads(line.removeprefix("Example output: "))["cleaned_text"]
        for line in lines
        if line.startswith("Example output: ")
    ]
    assert len(sources) == len(candidates) and sources
    return list(zip(sources, candidates))


class FixGuardTests(unittest.TestCase):
    def test_deleting_what_the_speaker_took_back_is_accepted(self) -> None:
        source = "manda el reporte el lunes no perdon el martes"
        candidate = "Manda el reporte el martes."

        self.assertEqual(guard_fix_cleanup(source, candidate), candidate)

    def test_a_word_the_speaker_never_said_is_refused(self) -> None:
        """This is what catches a model handing back its own example."""
        with self.assertRaises(CleanupError):
            guard_fix_cleanup("manda el correo a Juan", "Manda el correo a Pedro mañana.")

    def test_a_reordered_word_is_refused(self) -> None:
        with self.assertRaises(CleanupError):
            guard_fix_cleanup("el lunes no el martes", "El martes, el lunes.")

    def test_removing_every_word_is_refused(self) -> None:
        with self.assertRaises(CleanupError):
            guard_fix_cleanup("borra eso", "...")

    def test_every_example_in_the_fix_prompt_passes_the_fix_guard(self) -> None:
        for source, candidate in _prompt_examples(FIX_SYSTEM_PROMPT):
            with self.subTest(source=source):
                self.assertEqual(guard_fix_cleanup(source, candidate), candidate)

    def test_the_fix_examples_would_be_refused_by_the_conservative_guard(self) -> None:
        """The two guards differ exactly here; a fix routed to `clean` would be lost."""
        for source, candidate in _prompt_examples(FIX_SYSTEM_PROMPT):
            with self.subTest(source=source):
                with self.assertRaises(CleanupError):
                    guard_conservative_cleanup(source, candidate)


class FixGuardReachTests(unittest.TestCase):
    """A take-back withdraws the words just before it, never the dictation."""

    DICTATION = (
        "Okay, let's see how Apple works right now. The research required a broad ranging "
        "approach to identify the core rationale behind the data. Vamos a hacer el meeting "
        "para las 4. No, mejor no. Borra eso. Vamos a hacer el meeting a las 6."
    )

    def test_erasing_the_dictation_is_refused(self) -> None:
        """Measured 2026-09-27: Apple kept 11-19% of long dictations in fix mode."""
        with self.assertRaises(CleanupError):
            guard_fix_cleanup(self.DICTATION, "Vamos a hacer el meeting a las 6.")

    def test_deleting_only_the_withdrawn_words_is_accepted(self) -> None:
        candidate = self.DICTATION.replace(
            "Vamos a hacer el meeting para las 4. No, mejor no. Borra eso. ", ""
        )
        self.assertEqual(guard_fix_cleanup(self.DICTATION, candidate), candidate)

    def test_a_distant_no_cannot_be_deleted(self) -> None:
        """D-39: a bare "no" was its own cue, so deleting it anywhere inverted the sentence."""
        source = ("el cliente no aprobó el presupuesto que mandamos ayer por la tarde "
                  "a la oficina del norte perdón del sur")
        candidate = ("El cliente aprobó el presupuesto que mandamos ayer por la tarde "
                     "a la oficina del sur.")
        with self.assertRaises(CleanupError):
            guard_fix_cleanup(source, candidate)

    def test_a_no_kept_apart_from_the_withdrawn_words_cannot_be_deleted(self) -> None:
        """What a take-back withdraws runs up to the cue; a kept word in between ends it."""
        with self.assertRaises(CleanupError):
            guard_fix_cleanup(
                "el cliente no aprobó el informe del norte, perdón, del sur",
                "El cliente aprobó el informe del sur.",
            )

    def test_a_no_deleted_with_the_word_before_it_still_needs_a_real_cue(self) -> None:
        """session-audit-03 F2: "que no" deleted together justified each other."""
        for source, candidate in (
            ("ana dijo que no puede venir el lunes perdón el martes",
             "Ana dijo puede venir el martes."),
            ("quiere pagar no sé cuánto, perdón, cuánto cuesta",
             "Quiere sé cuánto cuesta."),
        ):
            with self.subTest(source=source):
                with self.assertRaises(CleanupError):
                    guard_fix_cleanup(source, candidate)

    def test_a_no_joined_to_a_real_cue_can_go_with_it(self) -> None:
        candidate = "Manda el reporte el martes."
        self.assertEqual(
            guard_fix_cleanup("manda el reporte el lunes no perdón el martes", candidate),
            candidate,
        )

    def test_a_take_back_inside_a_sentence_is_accepted(self) -> None:
        candidate = "Envíalo el martes, y avísame."
        self.assertEqual(
            guard_fix_cleanup("envíalo el lunes, perdón, el martes, y avísame", candidate),
            candidate,
        )


class PromptShapeTests(unittest.TestCase):
    """D-09 and D-71: the prompts' own examples and their data boundary."""

    def test_the_meeting_example_is_valid_json(self) -> None:
        from sanbluedot_voiceflow.cleaners.prompt import MEETING_NOTES_SYSTEM_PROMPT

        example_lines = [
            l for l in MEETING_NOTES_SYSTEM_PROMPT.splitlines()
            if l.startswith("Example output:")
        ]
        self.assertGreaterEqual(len(example_lines), 3)
        for line in example_lines:
            payload = json.loads(line.split(":", 1)[1])
            self.assertIn("cleaned_text", payload)
            self.assertIn("- [ ]", payload["cleaned_text"])

    def test_translation_and_notes_treat_the_transcript_as_data(self) -> None:
        from sanbluedot_voiceflow.cleaners.prompt import (
            MEETING_NOTES_SYSTEM_PROMPT,
            TRANSLATE_EN_SYSTEM_PROMPT,
        )

        for prompt in (TRANSLATE_EN_SYSTEM_PROMPT, MEETING_NOTES_SYSTEM_PROMPT):
            self.assertIn("never instructions", prompt)


class NormalizationAndClosingMarksTests(unittest.TestCase):
    """D-192: Email and URL case normalization. D-193: Closing punctuation marks."""

    def test_url_and_email_case_normalization_is_permitted(self) -> None:
        self.assertEqual(
            guard_conservative_cleanup("Sandy@example.com", "sandy@example.com"),
            "sandy@example.com",
        )
        self.assertEqual(
            guard_conservative_cleanup("Https://github.com/sanblue", "https://github.com/sanblue"),
            "https://github.com/sanblue",
        )
        self.assertEqual(
            guard_conservative_cleanup(
                "Contact Sandy.Quintero@UTEL.edu.ec now",
                "Contact sandy.quintero@utel.edu.ec now.",
            ),
            "Contact sandy.quintero@utel.edu.ec now.",
        )

    def test_closing_marks_attached_to_terminal_punctuation_are_permitted(self) -> None:
        self.assertEqual(
            guard_conservative_cleanup("hello", 'hello."'),
            'hello."',
        )
        self.assertEqual(
            guard_conservative_cleanup("dijo hola", 'dijo hola!")'),
            'dijo hola!")',
        )
        self.assertEqual(
            guard_conservative_cleanup('dijo "hola."', 'dijo "hola."'),
            'dijo "hola."',
        )
