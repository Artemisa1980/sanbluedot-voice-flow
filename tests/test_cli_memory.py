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
from sanbluedot_voiceflow.memory import CorrectionStore


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
        self.store.add("ies", "IESS")
        destination = self.root / "memory-export.json"

        with patch("sanbluedot_voiceflow.memory.CorrectionStore", lambda *_a, **_k: self.store):
            status, text = self.run_command(cli._export, Namespace(to=destination))

        self.assertEqual(status, 0)
        self.assertIn("Audio is not included", text)
        payload = json.loads(destination.read_text(encoding="utf-8"))
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual([c["heard"] for c in payload["corrections"]], ["ies"])
        self.assertIn("vocabulary", payload)


if __name__ == "__main__":
    unittest.main()
