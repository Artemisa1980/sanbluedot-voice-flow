import json
import tempfile
import unittest
from argparse import Namespace
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from sanbluedot_voiceflow import cli
from sanbluedot_voiceflow.errors import CleanupFailed, VoiceFlowError
from sanbluedot_voiceflow.contracts import PipelineResult
from sanbluedot_voiceflow.memory import CorrectionStore
from sanbluedot_voiceflow.snippets import SnippetStore


class CliTests(unittest.TestCase):
    @staticmethod
    def _process_args(**overrides: object) -> Namespace:
        """One `process` argument set, matching what the parser produces."""
        defaults: dict[str, object] = {
            "audio": Path("sample.wav"),
            "whisper_bin": "whisper-cli",
            "whisper_model": Path("model.bin"),
            "language": "auto",
            "cleaner": "literal",
            "mode": "clean",
            "gemini_model": "gemini-3.7-flash",
            "copy": False,
            "json": False,
            "no_memory": True,
            "no_vocab_prompt": True,
            "distill": False,
            "context_text": None,
            "context_text_stdin": False,
            "app_name": None,
        }
        defaults.update(overrides)
        return Namespace(**defaults)

    def test_translate_without_a_rewriting_cleaner_is_refused(self) -> None:
        """`literal` returns the sentence it was given.

        The run delivered untranslated Spanish while the capsule said ES➔EN, because the
        refusal covered one mode and not the others.
        """
        args = self._process_args(mode="translate", cleaner="literal")

        stderr = StringIO()
        with redirect_stderr(stderr):
            status = cli._process(args)

        self.assertEqual(status, 1)
        self.assertIn("translate", stderr.getvalue())

    def test_meeting_without_a_rewriting_cleaner_is_refused(self) -> None:
        args = self._process_args(mode="meeting", cleaner="literal")

        stderr = StringIO()
        with redirect_stderr(stderr):
            status = cli._process(args)

        self.assertEqual(status, 1)
        self.assertIn("meeting", stderr.getvalue())

    def test_clean_stays_legal_with_the_literal_cleaner(self) -> None:
        """The refusal must not reach the default pairing.

        `clean` with `literal` is what the application starts in, and `actions` reaches
        the engine as `clean`. A refusal that widened to every mode would stop ordinary
        dictation.
        """
        args = self._process_args(mode="clean", cleaner="literal")
        result = PipelineResult(
            raw_text="hola",
            personalized_text="hola",
            final_text="hola",
            language="es",
            cleaner="literal",
        )

        with (
            patch.object(cli.DictationPipeline, "process", return_value=result),
            redirect_stdout(StringIO()),
            redirect_stderr(StringIO()),
        ):
            self.assertEqual(cli._process(args), 0)

    def test_cleanup_failure_copies_safe_fallback_when_requested(self) -> None:
        args = Namespace(
            audio=Path("sample.wav"),
            whisper_bin="whisper-cli",
            whisper_model=Path("model.bin"),
            language="auto",
            cleaner="literal",
            gemini_model="gemini-3.7-flash",
            copy=True,
            json=False,
            no_memory=True,
            no_vocab_prompt=True,
        )

        with (
            patch.object(
                cli.DictationPipeline,
                "process",
                side_effect=CleanupFailed("cleanup failed", "raw transcript"),
            ),
            patch.object(cli, "copy_text") as copy_text,
            redirect_stdout(StringIO()),
            redirect_stderr(StringIO()),
        ):
            status = cli._process(args)

        self.assertEqual(status, 2)
        copy_text.assert_called_once_with("raw transcript")

    def test_clipboard_failure_still_emits_the_safe_fallback(self) -> None:
        args = Namespace(
            audio=Path("sample.wav"),
            whisper_bin="whisper-cli",
            whisper_model=Path("model.bin"),
            language="auto",
            cleaner="apple",
            gemini_model="gemini-3.7-flash",
            copy=True,
            json=False,
            no_memory=True,
            no_vocab_prompt=True,
        )
        output = StringIO()

        with (
            patch.object(
                cli.DictationPipeline,
                "process",
                side_effect=CleanupFailed("cleanup failed", "palabras rescatadas"),
            ),
            patch.object(cli, "copy_text", side_effect=cli.VoiceFlowError("no clipboard")),
            redirect_stdout(output),
            redirect_stderr(StringIO()),
        ):
            status = cli._process(args)

        self.assertEqual(status, 1)
        self.assertIn("palabras rescatadas", output.getvalue())

    def test_clipboard_failure_still_emits_the_cleaned_transcript(self) -> None:
        args = Namespace(
            audio=Path("sample.wav"),
            whisper_bin="whisper-cli",
            whisper_model=Path("model.bin"),
            language="auto",
            cleaner="literal",
            gemini_model="gemini-3.7-flash",
            copy=True,
            json=False,
            no_memory=True,
            no_vocab_prompt=True,
        )
        output = StringIO()
        result = PipelineResult(
            raw_text="texto crudo",
            personalized_text="texto personalizado",
            final_text="Texto limpio.",
            language="es",
            cleaner="literal",
        )

        with (
            patch.object(cli.DictationPipeline, "process", return_value=result),
            patch.object(cli, "copy_text", side_effect=cli.VoiceFlowError("no clipboard")),
            redirect_stdout(output),
            redirect_stderr(StringIO()),
        ):
            status = cli._process(args)

        self.assertEqual(status, 1)
        self.assertIn("Texto limpio.", output.getvalue())

    def test_json_output_contains_all_transcript_layers(self) -> None:
        args = Namespace(
            audio=Path("sample.wav"),
            whisper_bin="whisper-cli",
            whisper_model=Path("model.bin"),
            language="auto",
            cleaner="literal",
            gemini_model="gemini-3.7-flash",
            copy=False,
            json=True,
            no_memory=True,
            no_vocab_prompt=True,
        )
        output = StringIO()
        result = PipelineResult(
            raw_text="hola testing",
            personalized_text="hola testing",
            final_text="Hola, testing.",
            language=None,
            cleaner="literal",
        )

        with (
            patch.object(cli.DictationPipeline, "process", return_value=result),
            redirect_stdout(output),
            redirect_stderr(StringIO()),
        ):
            status = cli._process(args)

        self.assertEqual(status, 0)
        self.assertEqual(
            json.loads(output.getvalue()),
            {
                "raw_text": "hola testing",
                "personalized_text": "hola testing",
                "final_text": "Hola, testing.",
                "language": None,
                "cleaner": "literal",
                "model": None,
                "used_fallback": False,
                "timings": {"transcribe_seconds": None, "cleanup_seconds": None},
            },
        )

    def test_json_reports_the_measured_stage_durations(self) -> None:
        args = self._process_args(json=True)
        output = StringIO()
        result = PipelineResult(
            raw_text="hola",
            personalized_text="hola",
            final_text="Hola.",
            language="es",
            cleaner="literal",
            transcribe_seconds=1.2345,
            cleanup_seconds=0.5,
        )

        with (
            patch.object(cli.DictationPipeline, "process", return_value=result),
            redirect_stdout(output),
            redirect_stderr(StringIO()),
        ):
            self.assertEqual(cli._process(args), 0)

        self.assertEqual(
            json.loads(output.getvalue())["timings"],
            {"transcribe_seconds": 1.234, "cleanup_seconds": 0.5},
        )

    def test_a_failed_cleanup_still_reports_what_it_measured(self) -> None:
        args = self._process_args(json=True)
        output = StringIO()
        failure = CleanupFailed(
            "provider down",
            raw_text="hola",
            fallback_text="hola",
            language="es",
            transcribe_seconds=0.9,
            cleanup_seconds=45.0,
        )

        with (
            patch.object(cli.DictationPipeline, "process", side_effect=failure),
            redirect_stdout(output),
            redirect_stderr(StringIO()),
        ):
            self.assertEqual(cli._process(args), 2)

        payload = json.loads(output.getvalue())
        self.assertTrue(payload["used_fallback"])
        self.assertEqual(
            payload["timings"],
            {"transcribe_seconds": 0.9, "cleanup_seconds": 45.0},
        )


class ProviderCommandTests(unittest.TestCase):
    def test_status_never_prints_the_key(self) -> None:
        secret = "not-a-real-key-fixture"
        output = StringIO()

        with patch.object(cli, "describe", return_value="configured"):
            with redirect_stdout(output):
                exit_code = cli.main(["provider", "status", "gemini"])

        self.assertEqual(exit_code, 0)
        self.assertIn("configured", output.getvalue())
        self.assertNotIn(secret, output.getvalue())

    def test_gemini_is_the_default_provider(self) -> None:
        with patch.object(cli, "describe", return_value="no key stored") as described:
            with redirect_stdout(StringIO()):
                cli.main(["provider", "status"])

        self.assertEqual(described.call_args.args[0], "gemini")

    def test_forgetting_an_absent_key_reports_a_nonzero_exit(self) -> None:
        with patch.object(cli, "delete_api_key", return_value=False):
            with redirect_stdout(StringIO()):
                exit_code = cli.main(["provider", "forget", "gemini"])

        self.assertEqual(exit_code, 1)

    def test_a_keychain_refusal_is_reported_without_a_traceback(self) -> None:
        errors = StringIO()

        with patch.object(
            cli,
            "store_api_key_interactively",
            side_effect=VoiceFlowError("The gemini key was not stored."),
        ):
            with redirect_stdout(StringIO()), redirect_stderr(errors):
                exit_code = cli.main(["provider", "set-key", "gemini"])

        self.assertEqual(exit_code, 1)
        self.assertIn("was not stored", errors.getvalue())

    def test_a_keychain_deletion_failure_is_reported_without_claiming_absence(self) -> None:
        errors = StringIO()

        with patch.object(
            cli,
            "delete_api_key",
            side_effect=VoiceFlowError("The gemini key was not removed."),
        ):
            with redirect_stdout(StringIO()), redirect_stderr(errors):
                exit_code = cli.main(["provider", "forget", "gemini"])

        self.assertEqual(exit_code, 1)
        self.assertIn("not removed", errors.getvalue())
        self.assertNotIn("no key was stored", errors.getvalue())


class DistillationConsentTests(unittest.TestCase):
    """Keeping the spoken text on disk happens only when this run asked for it."""

    def _gemini_result(self) -> PipelineResult:
        return PipelineResult(
            raw_text="hola que tal",
            personalized_text="hola que tal",
            final_text="Hello, how are you?",
            language="es",
            cleaner="gemini",
        )

    def test_cloud_cleanup_alone_records_nothing(self) -> None:
        args = CliTests._process_args(cleaner="gemini", no_memory=False)

        # Memory stays on, as in daily use, but in a temporary folder: with the real
        # stores unpatched every suite run read the owner's corrections and snippets,
        # and a damaged one would have been quarantined by a test (D-131).
        with (
            tempfile.TemporaryDirectory() as temp_dir,
            patch.object(
                cli,
                "CorrectionStore",
                lambda *_a, **_k: CorrectionStore(Path(temp_dir) / "corrections.local.json"),
            ),
            patch.object(
                cli,
                "SnippetStore",
                lambda *_a, **_k: SnippetStore(Path(temp_dir) / "snippets.local.json"),
            ),
            patch.object(
                cli.DictationPipeline, "process", return_value=self._gemini_result()
            ),
            patch.object(cli.DistillationStore, "record") as record,
            redirect_stdout(StringIO()),
            redirect_stderr(StringIO()),
        ):
            self.assertEqual(cli._process(args), 0)

        record.assert_not_called()

    def test_the_flag_is_what_records_the_pair(self) -> None:
        args = CliTests._process_args(cleaner="gemini", distill=True)

        with (
            patch.object(
                cli.DictationPipeline, "process", return_value=self._gemini_result()
            ),
            patch.object(cli.DistillationStore, "record") as record,
            redirect_stdout(StringIO()),
            redirect_stderr(StringIO()),
        ):
            self.assertEqual(cli._process(args), 0)

        record.assert_called_once()
        self.assertEqual(record.call_args.kwargs["raw_text"], "hola que tal")

    def test_a_local_cleaner_cannot_record_a_pair_and_says_so(self) -> None:
        """A pair is the cloud rewrite beside the engine transcript.

        A local cleaner has no cloud side to store, so the flag records nothing. Saying
        nothing left the speaker believing a store was filling that was not, which is
        what R5c forbids.
        """
        args = CliTests._process_args(cleaner="apple", distill=True)
        result = PipelineResult(
            raw_text="hola que tal",
            personalized_text="hola que tal",
            final_text="Hola, ¿qué tal?",
            language="es",
            cleaner="apple",
        )
        errors = StringIO()

        with (
            patch.object(cli.DictationPipeline, "process", return_value=result),
            patch.object(cli.DistillationStore, "record") as record,
            redirect_stdout(StringIO()),
            redirect_stderr(errors),
        ):
            self.assertEqual(cli._process(args), 0)

        record.assert_not_called()
        self.assertIn("No distillation pair was recorded", errors.getvalue())

    def test_a_failed_recording_is_reported_not_swallowed(self) -> None:
        args = CliTests._process_args(cleaner="gemini", distill=True)
        errors = StringIO()

        with (
            patch.object(
                cli.DictationPipeline, "process", return_value=self._gemini_result()
            ),
            patch.object(
                cli.DistillationStore,
                "record",
                side_effect=OSError("Read-only file system"),
            ),
            redirect_stdout(StringIO()),
            redirect_stderr(errors),
        ):
            self.assertEqual(cli._process(args), 0)

        self.assertIn("was not recorded", errors.getvalue())

    def test_clear_refuses_without_the_confirmation(self) -> None:
        errors = StringIO()

        with (
            patch.object(cli.DistillationStore, "clear") as clear,
            redirect_stdout(StringIO()),
            redirect_stderr(errors),
        ):
            self.assertEqual(cli.main(["distill", "clear"]), 1)

        clear.assert_not_called()
        self.assertIn("--yes", errors.getvalue())

    def test_clear_with_confirmation_deletes_and_reports_the_count(self) -> None:
        output = StringIO()

        with (
            patch.object(cli.DistillationStore, "clear", return_value=7) as clear,
            redirect_stdout(output),
            redirect_stderr(StringIO()),
        ):
            self.assertEqual(cli.main(["distill", "clear", "--yes"]), 0)

        clear.assert_called_once_with()
        self.assertIn("Deleted 7 distillation pair(s)", output.getvalue())


class DistillCommandTests(unittest.TestCase):
    def test_distill_list_empty(self) -> None:
        output = StringIO()
        with patch.object(cli.DistillationStore, "load_all", return_value=[]):
            with patch.object(cli.DistillationStore, "count_by_mode", return_value={}):
                with redirect_stdout(output):
                    exit_code = cli.main(["distill", "list"])

        self.assertEqual(exit_code, 0)
        self.assertIn("0 total pair(s)", output.getvalue())

    def test_distill_record_command(self) -> None:
        output = StringIO()
        pair_mock = cli.DistillationPair(
            raw_text="hola",
            cleaned_text="Hello.",
            mode="translate",
            cleaner="gemini",
        )
        with patch.object(cli.DistillationStore, "record", return_value=pair_mock):
            with redirect_stdout(output):
                exit_code = cli.main(["distill", "record", "--raw", "hola", "--cleaned", "Hello.", "--mode", "translate"])

        self.assertEqual(exit_code, 0)
        self.assertIn("Recorded distillation pair [translate]: Hello.", output.getvalue())

    def test_distill_modelfile_stdout(self) -> None:
        output = StringIO()
        with patch.object(cli.DistillationStore, "load_all", return_value=[]):
            with redirect_stdout(output):
                exit_code = cli.main(["distill", "modelfile", "--mode", "translate"])

        self.assertEqual(exit_code, 0)
        self.assertIn("FROM qwen2.5:3b", output.getvalue())
        self.assertIn("PARAMETER temperature 0", output.getvalue())

    def test_distill_export_handles_os_error(self) -> None:
        errors = StringIO()
        with patch.object(cli.DistillationStore, "export_jsonl", side_effect=PermissionError("Read-only file system")):
            with redirect_stdout(StringIO()), redirect_stderr(errors):
                exit_code = cli.main(["distill", "export", "--to", "/root/export.jsonl"])

        self.assertEqual(exit_code, 1)
        self.assertIn("Read-only file system", errors.getvalue())

    def test_fix_without_a_rewriting_cleaner_is_refused(self) -> None:
        """`literal` cannot resolve a self-correction; a fix it ran would change nothing."""
        errors = StringIO()
        with (
            patch.object(cli.sys, "stdin", StringIO("el lunes no perdon el martes")),
            redirect_stdout(StringIO()),
            redirect_stderr(errors),
        ):
            status = cli.main(["clean", "--mode", "fix", "--cleaner", "literal", "--no-memory"])

        self.assertEqual(status, 1)
        self.assertIn("fix", errors.getvalue())

    def test_clean_json_carries_every_field_the_app_decodes(self) -> None:
        """The app decodes `personalized_text` as required; a reply without it failed."""
        output = StringIO()
        with (
            patch.object(cli.sys, "stdin", StringIO("hola mundo")),
            redirect_stdout(output),
            redirect_stderr(StringIO()),
        ):
            status = cli.main(["clean", "--cleaner", "literal", "--no-memory", "--json"])

        payload = json.loads(output.getvalue())
        self.assertEqual(status, 0)
        self.assertEqual(payload["personalized_text"], "hola mundo")
        self.assertIn("timings", payload)

    def test_clean_json_fallback_carries_the_same_fields(self) -> None:
        failure = CleanupFailed(
            "refused",
            raw_text="hola mundo",
            fallback_text="hola mundo",
            cleanup_seconds=0.5,
            reason="guard",
            rejected_text="Hola, mundo nuevo.",
        )
        output = StringIO()
        with (
            patch.object(cli.sys, "stdin", StringIO("hola mundo")),
            patch.object(cli.DictationPipeline, "process_text", side_effect=failure),
            redirect_stdout(output),
            redirect_stderr(StringIO()),
        ):
            status = cli.main(["clean", "--cleaner", "apple", "--no-memory", "--json"])

        payload = json.loads(output.getvalue())
        self.assertEqual(status, 2)
        self.assertEqual(payload["personalized_text"], "hola mundo")
        self.assertEqual(payload["timings"]["cleanup_seconds"], 0.5)
        self.assertEqual(payload["fallback_reason"], "guard")


if __name__ == "__main__":
    unittest.main()
