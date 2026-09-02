import json
import tempfile
import unittest
from argparse import Namespace
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import Mock, patch

from scripts import replay
from sanbluedot_voiceflow.contracts import PipelineResult
from sanbluedot_voiceflow.errors import VoiceFlowError
from sanbluedot_voiceflow.errors import CleanupFailed


class ReplayEvidenceTests(unittest.TestCase):
    def write_run(
        self,
        root: Path,
        corpus: list[dict[str, object]],
        results: list[dict[str, object]],
    ) -> tuple[Path, Path]:
        corpus_path = root / "corpus.json"
        results_path = root / "results.jsonl"
        corpus_path.write_text(json.dumps(corpus), encoding="utf-8")
        results_path.write_text(
            "\n".join(json.dumps(item) for item in results),
            encoding="utf-8",
        )
        return corpus_path, results_path

    def test_duplicate_result_sequences_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            corpus, results = self.write_run(
                root,
                [{"id": 1, "reference": "one"}],
                [
                    {"sequence": 1, "audio_file": "one.wav"},
                    {"sequence": 1, "audio_file": "two.wav"},
                ],
            )

            with self.assertRaises(ValueError):
                replay.load_samples(corpus, results)

    def test_complete_replay_rejects_missing_audio(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            corpus, results = self.write_run(
                root,
                [{"id": 1, "reference": "one"}],
                [{"sequence": 1, "audio_file": "missing.wav"}],
            )

            with self.assertRaises(ValueError):
                replay.load_samples(corpus, results, require_complete=True)

    def test_duplicate_audio_evidence_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "one.wav").write_bytes(b"audio")
            corpus, results = self.write_run(
                root,
                [{"id": 1, "reference": "one"}, {"id": 2, "reference": "two"}],
                [
                    {"sequence": 1, "audio_file": "one.wav"},
                    {"sequence": 2, "audio_file": "one.wav"},
                ],
            )

            with self.assertRaises(ValueError):
                replay.load_samples(corpus, results, require_complete=True)

    def test_audio_outside_the_results_directory_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            run = root / "run"
            run.mkdir()
            (root / "outside.wav").write_bytes(b"audio")
            corpus, results = self.write_run(
                run,
                [{"id": 1, "reference": "one"}],
                [{"sequence": 1, "audio_file": "../outside.wav"}],
            )

            with self.assertRaises(ValueError):
                replay.load_samples(corpus, results, require_complete=True)

    def test_absolute_audio_path_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            outside = root / "outside.wav"
            outside.write_bytes(b"audio")
            run = root / "run"
            run.mkdir()
            corpus, results = self.write_run(
                run,
                [{"id": 1, "reference": "one"}],
                [{"sequence": 1, "audio_file": str(outside)}],
            )

            with self.assertRaises(ValueError):
                replay.load_samples(corpus, results, require_complete=True)

    def test_no_memory_disables_both_corrections_and_vocabulary(self) -> None:
        args = Namespace(
            no_memory=True,
            no_corrections=False,
            no_vocab_prompt=False,
            prompt_budget=600,
            whisper_model=Path("unused.bin"),
            whisper_bin="whisper-cli",
            language="auto",
            threads=None,
            beam_size=None,
            cleaner="literal",
            ollama_model="qwen3:4b",
            gemini_model="gemini-3.7-flash",
        )

        with patch.object(replay, "load_vocabulary", return_value=["UTEL"]):
            pipeline = replay.build_pipeline(args)

        self.assertEqual(pipeline._transcriber.initial_prompt, "")
        self.assertEqual(pipeline._corrections, ())

    def test_complete_replay_fails_if_one_pipeline_sample_fails(self) -> None:
        args = Namespace(
            corpus=Path("corpus.json"),
            results=Path("results.jsonl"),
            whisper_model=Path("model.bin"),
            whisper_bin="whisper-cli",
            language="auto",
            cleaner="literal",
            ollama_model="qwen3:4b",
            gemini_model="gemini-3.7-flash",
            no_vocab_prompt=False,
            prompt_budget=600,
            threads=None,
            beam_size=None,
            no_memory=True,
            no_corrections=False,
            require_complete=True,
            label="test",
        )
        samples = [
            {"id": 1, "category": "all", "reference": "one", "audio": Path("1.wav")},
            {"id": 2, "category": "all", "reference": "two", "audio": Path("2.wav")},
        ]
        pipeline = Mock()
        pipeline.process.side_effect = [
            PipelineResult("one", "one", "one", "en", "literal"),
            VoiceFlowError("broken sample"),
        ]

        with (
            patch.object(replay, "parse_args", return_value=args),
            patch.object(replay, "load_samples", return_value=samples),
            patch.object(replay, "build_pipeline", return_value=pipeline),
            redirect_stdout(StringIO()) as output,
            redirect_stderr(StringIO()),
        ):
            status = replay.main()

        self.assertEqual(status, 1)
        self.assertIn("vocab prompt   off", output.getvalue())

    def test_complete_replay_fails_if_cleanup_uses_a_fallback(self) -> None:
        args = Namespace(
            corpus=Path("corpus.json"),
            results=Path("results.jsonl"),
            whisper_model=Path("model.bin"),
            whisper_bin="whisper-cli",
            language="auto",
            cleaner="ollama",
            ollama_model="qwen3:4b",
            gemini_model="gemini-3.7-flash",
            no_vocab_prompt=False,
            prompt_budget=600,
            threads=None,
            beam_size=None,
            no_memory=False,
            no_corrections=False,
            require_complete=True,
            label="test",
        )
        pipeline = Mock()
        pipeline.process.side_effect = CleanupFailed(
            "unsafe cleanup",
            raw_text="one",
            fallback_text="one",
        )

        with (
            patch.object(replay, "parse_args", return_value=args),
            patch.object(replay, "load_samples", return_value=[
                {
                    "id": 1,
                    "category": "all",
                    "reference": "one",
                    "audio": Path("1.wav"),
                }
            ]),
            patch.object(replay, "build_pipeline", return_value=pipeline),
            redirect_stdout(StringIO()),
            redirect_stderr(StringIO()),
        ):
            status = replay.main()

        self.assertEqual(status, 1)


if __name__ == "__main__":
    unittest.main()
