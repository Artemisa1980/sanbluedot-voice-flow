"""CLI-level coverage for the memory commands.

These paths touch the owner's real files by default, so every test points the stores
at a temporary directory first. A test that reached the real paths would rewrite
personal data.
"""

import json
import tempfile
import unittest
from argparse import Namespace
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from sanbluedot_voiceflow import cli
from sanbluedot_voiceflow.distill import DistillationStore
from sanbluedot_voiceflow.memory import CorrectionStore, export_memory
from sanbluedot_voiceflow.snippets import SnippetStore


class MemoryCommandTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.root = Path(self._temp.name)
        self.store = CorrectionStore(self.root / "corrections.local.json")
        self.vocabulary = self.root / "vocabulary.local.txt"
        self.vocabulary.write_text("UTEL\nGim\n", encoding="utf-8")
        self._patches = [
            patch.object(cli, "CorrectionStore", lambda *_a, **_k: self.store),
            patch.object(cli, "DEFAULT_VOCABULARY", self.vocabulary),
            patch.object(cli, "load_vocabulary", lambda *_a, **_k: ["UTEL", "Gim"]),
        ]
        for item in self._patches:
            item.start()

    def tearDown(self) -> None:
        for item in self._patches:
            item.stop()
        self._temp.cleanup()

    def run_command(self, handler, args: Namespace) -> tuple[int, str]:
        output = StringIO()
        with redirect_stdout(output), redirect_stderr(output):
            status = handler(args)
        return status, output.getvalue()

    def test_correct_then_memory_shows_the_pair(self) -> None:
        status, _ = self.run_command(
            cli._correct, Namespace(heard="ies", intended="IESS", allow_global=True)
        )
        self.assertEqual(status, 0)

        status, text = self.run_command(cli._memory, Namespace())

        self.assertEqual(status, 0)
        self.assertIn("'ies' -> 'IESS'", text)
        self.assertIn("Corrections: 1 confirmed", text)

    def test_correct_rejects_a_half_empty_pair(self) -> None:
        status, text = self.run_command(
            cli._correct, Namespace(heard="   ", intended="IESS")
        )

        self.assertEqual(status, 1)
        self.assertIn("needs both", text)
        self.assertEqual(self.store.load(), [])

    def test_single_word_pair_requires_explicit_global_confirmation(self) -> None:
        status, text = self.run_command(
            cli._correct,
            Namespace(heard="a", intended="y", allow_global=False),
        )

        self.assertEqual(status, 1)
        self.assertIn("rewrites that word everywhere", text)
        self.assertEqual(self.store.load(), [])

    def test_forget_removes_a_pair_and_reports_an_unknown_one(self) -> None:
        self.store.add("ies", "IESS")

        status, _ = self.run_command(cli._forget, Namespace(heard="ies"))
        self.assertEqual(status, 0)
        self.assertEqual(self.store.load(), [])

        status, text = self.run_command(cli._forget, Namespace(heard="ies"))
        self.assertEqual(status, 1)
        self.assertIn("No confirmed correction", text)

    def test_export_writes_every_layer_into_one_file(self) -> None:
        # Every store is read from this test's own directory. Before `export_memory`
        # took one, it read the real vocabulary, practice, snippet and distillation
        # stores and copied the owner's own sentences into a temporary file on every
        # run of the suite.
        destination = self.root / "memory-export.json"
        vocabulary = self.root / "vocabulary.local.txt"
        vocabulary.write_text("IESS\n", encoding="utf-8")
        CorrectionStore(self.root / "corrections.local.json").add("ies", "IESS")
        SnippetStore(self.root / "snippets.local.json").add(
            "mi correo", "user@example.com"
        )
        DistillationStore(self.root / "distill_pairs.local.jsonl").record(
            "hola que tal", "Hola, ¿qué tal?"
        )

        written, counts = export_memory(
            destination, vocabulary=vocabulary, directory=self.root
        )

        self.assertEqual(written, destination)
        payload = json.loads(destination.read_text(encoding="utf-8"))
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual([c["heard"] for c in payload["corrections"]], ["ies"])
        self.assertEqual(payload["vocabulary"], ["IESS"])
        # The two stores this file used to omit while promising "every piece".
        self.assertEqual([s["trigger"] for s in payload["snippets"]], ["mi correo"])
        self.assertEqual(
            [p["raw_text"] for p in payload["distillation_pairs"]], ["hola que tal"]
        )
        self.assertEqual(counts["snippets"], 1)
        self.assertEqual(counts["distillation_pairs"], 1)
        self.assertEqual(counts["corrections"], 1)

    def test_the_export_command_names_what_it_carried(self) -> None:
        # Distillation pairs are the speaker's own sentences. An export that carries
        # them without saying so is not a decision they made.
        destination = self.root / "memory-export.json"
        counts = {"vocabulary": 3, "snippets": 1, "distillation_pairs": 12}

        with patch(
            "sanbluedot_voiceflow.cli.export_memory",
            lambda *_a, **_k: (destination, counts),
        ):
            status, text = self.run_command(cli._export, Namespace(to=destination))

        self.assertEqual(status, 0)
        self.assertIn("Audio is not included", text)
        self.assertIn("distillation pairs: 12", text)
        self.assertIn("snippets: 1", text)


if __name__ == "__main__":
    unittest.main()
