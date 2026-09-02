import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from sanbluedot_voiceflow.distill import (
    DEFAULT_BASE_MODEL,
    DistillationPair,
    DistillationStore,
    build_modelfile,
    create_ollama_model,
    write_modelfile,
)
from sanbluedot_voiceflow.errors import VoiceFlowError


class TestDistill(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.store_path = Path(self.temp_dir.name) / "distill.jsonl"
        self.store = DistillationStore(path=self.store_path)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_pair_serialization(self) -> None:
        pair = DistillationPair(
            raw_text="hola mundo",
            cleaned_text="Hello world.",
            mode="translate",
            cleaner="gemini",
            model="gemini-3.5-flash",
            timestamp="2026-09-01T12:00:00Z",
        )
        data = pair.to_dict()
        self.assertEqual(data["raw_text"], "hola mundo")
        self.assertEqual(data["cleaned_text"], "Hello world.")
        self.assertEqual(data["mode"], "translate")
        self.assertEqual(data["cleaner"], "gemini")

        recovered = DistillationPair.from_dict(data)
        self.assertEqual(recovered, pair)

    def test_pair_from_dict_validation(self) -> None:
        with self.assertRaises(ValueError):
            DistillationPair.from_dict({"raw_text": 123, "cleaned_text": "text"})
        with self.assertRaises(ValueError):
            DistillationPair.from_dict({"raw_text": "text", "cleaned_text": None})
        with self.assertRaises(ValueError):
            DistillationPair.from_dict({"raw_text": "  ", "cleaned_text": "valid"})

    def test_record_and_load_pairs(self) -> None:
        self.store.record("hola", "Hola.", mode="clean", cleaner="gemini")
        self.store.record("buenos dias", "Good morning.", mode="translate", cleaner="gemini")
        self.store.record("reunion manana", "- [ ] Reunion manana.", mode="meeting", cleaner="gemini")

        all_pairs = self.store.load_all()
        self.assertEqual(len(all_pairs), 3)

        translate_pairs = self.store.load_all(mode="translate")
        self.assertEqual(len(translate_pairs), 1)
        self.assertEqual(translate_pairs[0].cleaned_text, "Good morning.")

        counts = self.store.count_by_mode()
        self.assertEqual(counts, {"clean": 1, "translate": 1, "meeting": 1})

    def test_corrupted_lines_handled_gracefully(self) -> None:
        self.store.record("hola", "Hola.", mode="clean")
        with self.store_path.open("a", encoding="utf-8") as f:
            f.write("not json\n")
            f.write(json.dumps({"raw_text": 123}) + "\n")
        self.store.record("adios", "Adios.", mode="clean")

        pairs = self.store.load_all()
        self.assertEqual(len(pairs), 2)
        self.assertEqual(pairs[0].raw_text, "hola")
        self.assertEqual(pairs[1].raw_text, "adios")

    def test_record_empty_fails(self) -> None:
        with self.assertRaises(VoiceFlowError):
            self.store.record("", "Valid")
        with self.assertRaises(VoiceFlowError):
            self.store.record("Valid", "   ")

    def test_export_jsonl(self) -> None:
        self.store.record("uno", "One.", mode="translate")
        self.store.record("dos", "Two.", mode="translate")
        self.store.record("tres", "Tres.", mode="clean")

        export_path = Path(self.temp_dir.name) / "exported.jsonl"
        exported_count = self.store.export_jsonl(export_path, mode="translate")
        self.assertEqual(exported_count, 2)
        self.assertTrue(export_path.exists())

        lines = export_path.read_text(encoding="utf-8").strip().splitlines()
        self.assertEqual(len(lines), 2)
        data = json.loads(lines[0])
        self.assertEqual(data["cleaned_text"], "One.")

    def test_build_modelfile(self) -> None:
        pairs = [
            DistillationPair(
                raw_text="por favor envia el reporte",
                cleaned_text="Please send the report.",
                mode="translate",
                cleaner="gemini",
            )
        ]
        modelfile = build_modelfile(
            base_model="qwen2.5:3b",
            mode="translate",
            pairs=pairs,
        )

        self.assertIn("FROM qwen2.5:3b", modelfile)
        self.assertIn("PARAMETER temperature 0", modelfile)
        self.assertIn("PARAMETER stop \"<|eot_id|>\"", modelfile)
        self.assertIn("Translate a spoken voice transcript", modelfile)
        self.assertIn("MESSAGE user", modelfile)
        self.assertIn("por favor envia el reporte", modelfile)
        self.assertIn("Please send the report.", modelfile)

    def test_build_modelfile_triple_quote_escaping(self) -> None:
        pairs = [
            DistillationPair(
                raw_text='Say """hello""" and goodbye',
                cleaned_text='Print """result""" to screen',
                mode="clean",
                cleaner="gemini",
            )
        ]
        modelfile = build_modelfile(pairs=pairs)
        self.assertNotIn('MESSAGE user """Say """hello"""', modelfile)
        self.assertIn(r'\"\"\"hello\"\"\"', modelfile)

    def test_invalid_base_model_rejected(self) -> None:
        with self.assertRaises(VoiceFlowError):
            build_modelfile(base_model="malicious\nFROM hacked")

    def test_write_modelfile(self) -> None:
        out_path = Path(self.temp_dir.name) / "Modelfile"
        pairs = [
            DistillationPair(
                raw_text="hola",
                cleaned_text="Hola.",
                mode="clean",
                cleaner="gemini",
            )
        ]
        res = write_modelfile(out_path, base_model=DEFAULT_BASE_MODEL, pairs=pairs)
        self.assertEqual(res, out_path)
        self.assertTrue(out_path.exists())
        content = out_path.read_text(encoding="utf-8")
        self.assertIn("FROM qwen2.5:3b", content)
        self.assertIn("Hola.", content)

    @patch("sanbluedot_voiceflow.distill.urlopen")
    def test_create_ollama_model_success(self, mock_urlopen: MagicMock) -> None:
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({"status": "success"}).encode("utf-8")
        mock_response.__enter__.return_value = mock_response
        mock_urlopen.return_value = mock_response

        success = create_ollama_model("test-model", "FROM qwen2.5:3b")
        self.assertTrue(success)

    @patch("sanbluedot_voiceflow.distill.urlopen")
    def test_create_ollama_model_error_payload(self, mock_urlopen: MagicMock) -> None:
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({"error": "model pull failed"}).encode("utf-8")
        mock_response.__enter__.return_value = mock_response
        mock_urlopen.return_value = mock_response

        with self.assertRaises(VoiceFlowError) as ctx:
            create_ollama_model("test-model", "FROM qwen2.5:3b")
        self.assertIn("model pull failed", str(ctx.exception))

    @patch("sanbluedot_voiceflow.distill.urlopen")
    def test_create_ollama_model_failure(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.side_effect = OSError("Connection refused")
        with self.assertRaises(VoiceFlowError):
            create_ollama_model("test-model", "FROM qwen2.5:3b")


class DistillationStoreClearTests(unittest.TestCase):
    def test_clear_removes_every_pair_and_the_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = DistillationStore(Path(directory) / "pairs.local.jsonl")
            store.record(raw_text="hola", cleaned_text="Hello.")
            store.record(raw_text="adios", cleaned_text="Goodbye.")

            removed = store.clear()

            self.assertEqual(removed, 2)
            self.assertFalse(store.path.exists())
            self.assertEqual(store.load_all(), [])

    def test_clear_on_an_absent_store_reports_zero(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = DistillationStore(Path(directory) / "pairs.local.jsonl")
            self.assertEqual(store.clear(), 0)


class DistillationExportSafetyTests(unittest.TestCase):
    """Exporting onto the store must never be a way to delete pairs."""

    def test_export_onto_the_store_is_refused_and_changes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = DistillationStore(Path(directory) / "pairs.local.jsonl")
            store.record(raw_text="uno", cleaned_text="One.", mode="clean")
            store.record(raw_text="dos", cleaned_text="Two.", mode="translate")
            store.record(raw_text="tres", cleaned_text="Three.", mode="meeting")

            with self.assertRaises(VoiceFlowError):
                store.export_jsonl(store.path, mode="clean")

            self.assertEqual(len(store.load_all()), 3)

    def test_export_to_another_path_still_works(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = DistillationStore(Path(directory) / "pairs.local.jsonl")
            store.record(raw_text="uno", cleaned_text="One.", mode="clean")
            store.record(raw_text="dos", cleaned_text="Two.", mode="translate")

            written = store.export_jsonl(Path(directory) / "out.jsonl", mode="clean")

            self.assertEqual(written, 1)
            self.assertEqual(len(store.load_all()), 2)


if __name__ == "__main__":
    unittest.main()
