import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import MagicMock, patch

from sanbluedot_voiceflow import cli
from sanbluedot_voiceflow.contracts import Transcript
from sanbluedot_voiceflow.errors import CleanupError, CleanupFailed, VoiceFlowError
from sanbluedot_voiceflow.pipeline import DictationPipeline
from sanbluedot_voiceflow.snippets import (
    Snippet,
    SnippetStore,
    expand_snippets,
)


class TestSnippets(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.store_path = Path(self.temp_dir.name) / "snippets.json"
        self.store = SnippetStore(path=self.store_path)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_snippet_serialization(self) -> None:
        snip = Snippet(
            trigger="mi linkedin",
            expansion="https://example.com/in/fixture-profile",
            description="Enlace de perfil",
        )
        data = snip.to_dict()
        self.assertEqual(data["trigger"], "mi linkedin")
        self.assertEqual(data["expansion"], "https://example.com/in/fixture-profile")
        self.assertEqual(data["description"], "Enlace de perfil")

        recovered = Snippet.from_dict(data)
        self.assertEqual(recovered, snip)

    def test_snippet_validation(self) -> None:
        with self.assertRaises(ValueError):
            Snippet.from_dict({"trigger": 123, "expansion": "url"})
        with self.assertRaises(ValueError):
            Snippet.from_dict({"trigger": "   ", "expansion": "url"})
        with self.assertRaises(ValueError):
            Snippet.from_dict("not a dict")  # type: ignore[arg-type]

    def test_expand_snippets_case_insensitive_and_word_boundaries(self) -> None:
        snippets = [
            Snippet(trigger="mi linkedin", expansion="https://example.com/profile"),
            Snippet(trigger="mi linkedin corporativo", expansion="https://linkedin.com/company/sanblue"),
            Snippet(trigger="mi correo", expansion="user@example.com"),
        ]

        text = "Por favor visita Mi LinkedIn o envíame un mensaje a Mi Correo."
        expanded = expand_snippets(text, snippets)
        self.assertEqual(
            expanded,
            "Por favor visita https://example.com/profile o envíame un mensaje a user@example.com.",
        )

        # Longest match first check
        corp_text = "Revisa Mi LinkedIn Corporativo para más detalles."
        corp_expanded = expand_snippets(corp_text, snippets)
        self.assertEqual(
            corp_expanded,
            "Revisa https://linkedin.com/company/sanblue para más detalles.",
        )

    def test_expand_snippets_dynamic_macros(self) -> None:
        from datetime import datetime
        fixed_time = datetime(2026, 9, 3, 10, 15)
        snippets = [
            Snippet(trigger="fecha de hoy", expansion="{date}"),
            Snippet(trigger="hora actual", expansion="{time}"),
            Snippet(trigger="timestamp completo", expansion="{datetime}"),
            Snippet(trigger="plantilla reporte", expansion="Reporte {year}-{month}-{day}"),
            Snippet(trigger="nuevo uuid", expansion="{uuid}"),
        ]

        text = "Por favor genera el reporte fecha de hoy a las hora actual. timestamp completo"
        expanded = expand_snippets(text, snippets, now=fixed_time)
        self.assertEqual(
            expanded,
            "Por favor genera el reporte 2026-09-03 a las 10:15. 2026-09-03 10:15",
        )

        # The date parts are numeric and agree with each other. `%A` wrote an English
        # weekday into a Spanish template regardless of the speaker's language.
        template_expanded = expand_snippets("Crea plantilla reporte", snippets, now=fixed_time)
        self.assertEqual(template_expanded, "Crea Reporte 2026-09-03")

        uuid_text = "Asigna nuevo uuid"
        uuid_expanded = expand_snippets(uuid_text, snippets)
        self.assertNotIn("{uuid}", uuid_expanded)
        self.assertTrue(uuid_expanded.startswith("Asigna "))

    def test_app_macro_resolves_and_stays_visible_when_unknown(self) -> None:
        snippets = [Snippet(trigger="app actual", expansion="Escrito desde {app}")]

        self.assertEqual(
            expand_snippets("Nota: app actual", snippets, app_name="VS Code"),
            "Nota: Escrito desde VS Code",
        )
        # No caller knew the application: the macro is left where the speaker can see
        # that it did not resolve, rather than pasted as a blank.
        self.assertEqual(
            expand_snippets("Nota: app actual", snippets),
            "Nota: Escrito desde {app}",
        )

    def test_expand_snippets_literal_backslashes_and_group_references(self) -> None:
        snippets = [
            Snippet(trigger="ruta windows", expansion=r"C:\Users\Fixture\Documents\file.txt"),
            Snippet(trigger="formula latex", expansion=r"\frac{a}{b} + \sqrt{x}"),
            Snippet(trigger="precio", expansion="$100 USD (código: \\g<1>)"),
        ]

        text = "Guarda el archivo en ruta windows con formula latex y precio."
        expanded = expand_snippets(text, snippets)
        self.assertEqual(
            expanded,
            r"Guarda el archivo en C:\Users\Fixture\Documents\file.txt con \frac{a}{b} + \sqrt{x} y $100 USD (código: \g<1>).",
        )

    def test_expand_snippets_non_cascading_single_scan(self) -> None:
        # Snippet 1 expansion contains Snippet 2's trigger. Single scan must not cascade.
        snippets = [
            Snippet(trigger="mi correo", expansion="hello@example.dev"),
            Snippet(trigger="sanblue", expansion="Sanblue LLC"),
        ]

        text = "Escríbeme a mi correo para más información."
        expanded = expand_snippets(text, snippets)
        self.assertEqual(expanded, "Escríbeme a hello@example.dev para más información.")

    def test_store_crud_and_clear(self) -> None:
        self.assertEqual(self.store.load(), [])

        self.store.add("mi web", "https://sanblue.dev")
        self.store.add("firma", "Saludos,\nFixture", "Firma corta")
        self.assertEqual(len(self.store.load()), 2)

        # Overwrite existing trigger
        self.store.add("mi web", "https://sanbluedot.com")
        snippets = self.store.load()
        self.assertEqual(len(snippets), 2)
        web_snip = next(s for s in snippets if s.trigger == "mi web")
        self.assertEqual(web_snip.expansion, "https://sanbluedot.com")

        # Delete
        self.assertTrue(self.store.delete("mi web"))
        self.assertFalse(self.store.delete("no existe"))
        self.assertEqual(len(self.store.load()), 1)

        # Clear
        self.store.clear()
        self.assertEqual(self.store.load(), [])

    def test_store_export_and_import(self) -> None:
        self.store.add("uno", "1")
        self.store.add("dos", "2")

        export_path = Path(self.temp_dir.name) / "exported.json"
        count = self.store.export_json(export_path)
        self.assertEqual(count, 2)

        new_store_path = Path(self.temp_dir.name) / "new_snippets.json"
        new_store = SnippetStore(path=new_store_path)
        imported_count = new_store.import_json(export_path)
        self.assertEqual(imported_count, 2)
        self.assertEqual(len(new_store.load()), 2)

    def test_store_quarantine_corrupt_or_unsupported_schema(self) -> None:
        self.store_path.write_text("invalid json content", encoding="utf-8")
        err_out = StringIO()
        with redirect_stderr(err_out):
            loaded = self.store.load()
        self.assertEqual(loaded, [])
        self.assertIn("could not be read", err_out.getvalue())

        # Schema version mismatch
        self.store_path.write_text('{"schema_version": 999, "snippets": []}', encoding="utf-8")
        err_out2 = StringIO()
        with redirect_stderr(err_out2):
            loaded_schema = self.store.load()
        self.assertEqual(loaded_schema, [])
        self.assertIn("unsupported schema version", err_out2.getvalue())

    def test_pipeline_expands_snippets(self) -> None:
        transcriber = MagicMock()
        transcriber.transcribe.return_value = Transcript(
            text="mira mi linkedin",
            language="es",
        )
        cleaner = MagicMock()
        cleaner.name = "literal"
        cleaner.mode = "clean"
        cleaner.clean.return_value = "Mira mi linkedin."

        snippets = [Snippet(trigger="mi linkedin", expansion="https://example.com/profile")]
        pipeline = DictationPipeline(
            transcriber=transcriber,
            cleaner=cleaner,
            snippets=snippets,
        )

        result = pipeline.process(Path("dummy.wav"))
        self.assertEqual(result.final_text, "Mira https://example.com/profile.")

    def test_pipeline_fallback_expands_snippets_on_cleanup_failure(self) -> None:
        transcriber = MagicMock()
        transcriber.transcribe.return_value = Transcript(
            text="visita mi web",
            language="es",
        )
        cleaner = MagicMock()
        cleaner.name = "gemini"
        cleaner.mode = "clean"
        cleaner.clean.side_effect = RuntimeError("API down")

        snippets = [Snippet(trigger="mi web", expansion="https://sanblue.dev")]
        pipeline = DictationPipeline(
            transcriber=transcriber,
            cleaner=cleaner,
            snippets=snippets,
        )

        with self.assertRaises(CleanupFailed) as ctx:
            pipeline.process(Path("dummy.wav"))
        self.assertEqual(ctx.exception.fallback_text, "visita https://sanblue.dev")


class TestSnippetCli(unittest.TestCase):
    def test_snippet_cli_list_empty(self) -> None:
        output = StringIO()
        with patch.object(cli.SnippetStore, "load", return_value=[]):
            with redirect_stdout(output):
                exit_code = cli.main(["snippet", "list"])
        self.assertEqual(exit_code, 0)
        self.assertIn("No voice snippets registered.", output.getvalue())

    def test_snippet_cli_add_and_delete(self) -> None:
        output = StringIO()
        snip_mock = Snippet("mi calendly", "https://calendly.com")
        with patch.object(cli.SnippetStore, "add", return_value=snip_mock):
            with redirect_stdout(output):
                exit_code = cli.main(["snippet", "add", "--trigger", "mi calendly", "--expansion", "https://calendly.com"])
        self.assertEqual(exit_code, 0)
        self.assertIn("Added voice snippet [mi calendly].", output.getvalue())

        output_del = StringIO()
        with patch.object(cli.SnippetStore, "delete", return_value=True):
            with redirect_stdout(output_del):
                exit_code_del = cli.main(["snippet", "delete", "--trigger", "mi calendly"])
        self.assertEqual(exit_code_del, 0)
        self.assertIn("Deleted voice snippet [mi calendly].", output_del.getvalue())

    def test_snippet_cli_delete_not_found(self) -> None:
        err_out = StringIO()
        with patch.object(cli.SnippetStore, "delete", return_value=False):
            with redirect_stderr(err_out):
                exit_code = cli.main(["snippet", "delete", "--trigger", "no_existe"])
        self.assertEqual(exit_code, 1)
        self.assertIn("Snippet [no_existe] not found.", err_out.getvalue())


if __name__ == "__main__":
    unittest.main()
