import json
import unittest

from sanbluedot_voiceflow.cleaners.ollama import OllamaCleaner, output_token_budget
from sanbluedot_voiceflow.errors import CleanupError


class FakeResponse:
    def __init__(self, payload: dict[str, object]) -> None:
        self._body = json.dumps(payload).encode("utf-8")

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def read(self) -> bytes:
        return self._body


class OllamaCleanerTests(unittest.TestCase):
    def test_sends_local_chat_request_and_returns_content(self) -> None:
        captured: dict[str, object] = {}

        def opener(request: object, timeout: float) -> FakeResponse:
            captured["url"] = request.full_url  # type: ignore[attr-defined]
            captured["payload"] = json.loads(request.data.decode("utf-8"))  # type: ignore[attr-defined]
            captured["timeout"] = timeout
            return FakeResponse(
                {"message": {"content": '{"cleaned_text": "Texto limpio."}'}}
            )

        cleaner = OllamaCleaner(opener=opener, timeout_seconds=4.0)
        result = cleaner.clean("texto um original", language_hint="es")

        self.assertEqual(result, "Texto limpio.")
        self.assertEqual(captured["url"], "http://127.0.0.1:11434/api/chat")
        payload = captured["payload"]
        self.assertEqual(payload["model"], "qwen3:4b")  # type: ignore[index]
        self.assertFalse(payload["stream"])  # type: ignore[index]
        self.assertFalse(payload["think"])  # type: ignore[index]
        self.assertEqual(payload["keep_alive"], "10m")  # type: ignore[index]
        self.assertEqual(payload["format"]["required"], ["cleaned_text"])  # type: ignore[index]
        self.assertEqual(payload["options"]["num_predict"], 2048)  # type: ignore[index]
        self.assertEqual(captured["timeout"], 4.0)

    def test_output_budget_grows_with_the_transcript(self) -> None:
        long_transcript = " ".join(["palabra"] * 400)

        self.assertEqual(output_token_budget("tres palabras aqui"), 2048)
        self.assertGreater(output_token_budget(long_transcript), 2048)

    def test_invalid_response_raises_cleanup_error(self) -> None:
        cleaner = OllamaCleaner(opener=lambda *_args, **_kwargs: FakeResponse({}))

        with self.assertRaises(CleanupError):
            cleaner.clean("text")

    def test_translate_mode_uses_translation_prompt(self) -> None:
        captured: dict[str, object] = {}

        def opener(request: object, timeout: float) -> FakeResponse:
            captured["payload"] = json.loads(request.data.decode("utf-8"))  # type: ignore[attr-defined]
            return FakeResponse(
                {"message": {"content": '{"cleaned_text": "Clean text in English."}'}}
            )

        cleaner = OllamaCleaner(mode="translate", opener=opener)
        result = cleaner.clean("texto original", language_hint="es")

        self.assertEqual(result, "Clean text in English.")
        messages = captured["payload"]["messages"]  # type: ignore[index]
        self.assertIn("Translate a spoken voice transcript", messages[0]["content"])

    def test_meeting_mode_uses_meeting_prompt(self) -> None:
        captured: dict[str, object] = {}

        def opener(request: object, timeout: float) -> FakeResponse:
            captured["payload"] = json.loads(request.data.decode("utf-8"))  # type: ignore[attr-defined]
            return FakeResponse(
                {"message": {"content": '{"cleaned_text": "### Action Items\\n- [ ] Task"}'}}
            )

        cleaner = OllamaCleaner(mode="meeting", opener=opener)
        result = cleaner.clean("reunión de hoy", language_hint="es")

        self.assertEqual(result, "### Action Items\n- [ ] Task")
        messages = captured["payload"]["messages"]  # type: ignore[index]
        self.assertIn("Format a spoken voice dictation into clear, structured Markdown meeting notes", messages[0]["content"])

    def test_transform_mode_uses_transform_prompt(self) -> None:
        captured: dict[str, object] = {}

        def opener(request: object, timeout: float) -> FakeResponse:
            captured["payload"] = json.loads(request.data.decode("utf-8"))  # type: ignore[attr-defined]
            return FakeResponse(
                {"message": {"content": '{"cleaned_text": "- Bullet point item"}'}}
            )

        cleaner = OllamaCleaner(mode="transform", opener=opener)
        result = cleaner.clean("Original text:\nHello world\n\nInstruction:\nmake it bullet points", language_hint="en")

        self.assertEqual(result, "- Bullet point item")
        messages = captured["payload"]["messages"]  # type: ignore[index]
        self.assertIn("Transform the input text according to the spoken voice instruction", messages[0]["content"])


if __name__ == "__main__":
    unittest.main()
