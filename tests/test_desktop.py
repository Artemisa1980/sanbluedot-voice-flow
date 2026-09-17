import tempfile
import unittest
from pathlib import Path
from sanbluedot_voiceflow.desktop import dispatch


class DesktopBridgeTests(unittest.TestCase):
    def test_snippet_description_survives_save_edit_and_read(self):
        self.call(action="snippet_save", trigger="my signature", expansion="Sandy", description="Work signature")
        entry = self.call(action="read")["snippets"][0]
        self.assertEqual(entry["description"], "Work signature")
        self.call(action="snippet_save", trigger=entry["trigger"], expansion="Sandy — updated", description=entry["description"])
        self.assertEqual(self.call(action="read")["snippets"][0]["description"], "Work signature")
        for bad in [123, "a\0b", "x" * 16001]:
            with self.assertRaises(ValueError):
                self.call(action="snippet_save", trigger="my signature", expansion="bad", description=bad)
        self.assertEqual(self.call(action="read")["snippets"][0]["expansion"], "Sandy — updated")
        self.call(action="snippet_save", trigger="my signature", expansion="Sandy", description=" ")
        self.assertNotIn("description", self.call(action="read")["snippets"][0])

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def call(self, **request):
        return dispatch(request, self.root)

    def test_read_is_empty_and_does_not_create_stores(self):
        result = self.call(action="read")
        self.assertEqual(result["snippets"], [])
        self.assertEqual(list(self.root.iterdir()), [])

    def test_unicode_snippet_round_trip_and_explicit_delete(self):
        self.call(action="snippet_save", trigger="mi firma", expansion="Español 日本語\nSecond line")
        result = self.call(action="read")
        self.assertEqual(result["snippets"][0]["expansion"], "Español 日本語\nSecond line")
        self.assertEqual(self.call(action="snippet_delete", trigger="mi firma")["snippets"], [])

    def test_global_correction_needs_boolean_confirmation(self):
        for allowed in [False, "true", 1]:
            with self.assertRaises(ValueError):
                self.call(action="correction_save", heard="cat", intended="CAT", allow_global=allowed)
        self.call(action="correction_save", heard="cat", intended="CAT", allow_global=True)
        self.assertEqual(len(self.call(action="read")["corrections"]), 1)
        self.assertEqual(self.call(action="correction_delete", heard="cat")["corrections"], [])

    def test_bad_inputs_never_mutate_the_store(self):
        for request in [dict(action="execute"), dict(action="snippet_save",trigger="",expansion="x"),
                        dict(action="snippet_save",trigger="x",expansion="a\0b")]:
            with self.assertRaises(ValueError):
                dispatch(request, self.root)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_corrupt_store_is_preserved_and_warning_reaches_the_hub(self):
        (self.root / "snippets.local.json").write_text("{", encoding="utf8")
        result = self.call(action="read")
        self.assertTrue(result["warning"])
        self.assertEqual(len(list(self.root.glob("*.corrupt-*"))), 1)
