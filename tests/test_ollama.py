import json
import unittest

from sanbluedot_voiceflow.cleaners.ollama import OllamaCleaner, output_token_budget
from sanbluedot_voiceflow.cleaners.prompt import (
    FIX_SYSTEM_PROMPT,
    MEETING_NOTES_SYSTEM_PROMPT,
    TRANSLATE_EN_SYSTEM_PROMPT,
)
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
        self.assertEqual(messages[0]["content"], TRANSLATE_EN_SYSTEM_PROMPT)

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
        self.assertEqual(messages[0]["content"], MEETING_NOTES_SYSTEM_PROMPT)

    def test_an_address_off_this_machine_is_refused_before_anything_is_sent(self) -> None:
        def opener(request: object, timeout: float) -> FakeResponse:
            raise AssertionError("the transcript left the machine")

        for url in ("http://example.com:11434", "http://192.168.1.20:11434"):
            with self.subTest(url=url):
                with self.assertRaises(CleanupError):
                    OllamaCleaner(base_url=url, opener=opener).clean("texto", "es")

    def test_a_take_back_runs_as_a_fix_for_that_call_only(self) -> None:
        """The pipeline passes `mode="fix"` when a clean dictation carries a take-back."""
        captured: list[str] = []

        def opener(request: object, timeout: float) -> FakeResponse:
            payload = json.loads(request.data.decode("utf-8"))  # type: ignore[attr-defined]
            captured.append(payload["messages"][0]["content"])
            return FakeResponse({"message": {"content": '{"cleaned_text": "A las 5."}'}})

        cleaner = OllamaCleaner(opener=opener)
        self.assertEqual(cleaner.clean("a las 4, no, mejor no, a las 5", "es", mode="fix"), "A las 5.")
        cleaner.clean("texto", "es")

        self.assertEqual(captured[0], FIX_SYSTEM_PROMPT)
        self.assertNotEqual(captured[1], FIX_SYSTEM_PROMPT)

if __name__ == "__main__":
    unittest.main()
