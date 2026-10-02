import json
import subprocess
import unittest

from sanbluedot_voiceflow.cleaners import build_cleaner
from sanbluedot_voiceflow.cleaners.apple import AppleCleaner
from sanbluedot_voiceflow.cleaners.prompt import (
    CONSERVATIVE_SYSTEM_PROMPT,
    TRANSLATE_EN_SYSTEM_PROMPT,
)
from sanbluedot_voiceflow.errors import CleanupError


class Recorder:
    """Stand in for the Swift binary, recording what the adapter sent it."""

    def __init__(self, stdout: str = "", stderr: str = "", returncode: int = 0) -> None:
        self.stdout = stdout
        self.stderr = stderr
        self.returncode = returncode
        self.commands: list[list[str]] = []
        self.inputs: list[str] = []

    def __call__(self, command, **kwargs):
        self.commands.append(command)
        self.inputs.append(kwargs.get("input", ""))
        return subprocess.CompletedProcess(
            command, self.returncode, stdout=self.stdout, stderr=self.stderr
        )


def answer(cleaned: str) -> str:
    return json.dumps({"cleaned_text": cleaned})


def build(recorder: Recorder, mode: str = "clean") -> AppleCleaner:
    # An absolute path, so the adapter resolves it without consulting PATH.
    return AppleCleaner(binary="/usr/bin/true", mode=mode, runner=recorder)


class AppleCleanerTests(unittest.TestCase):
    def test_the_cleaned_text_comes_back(self) -> None:
        recorder = Recorder(stdout=answer("El reporte va el jueves."))

        self.assertEqual(
            build(recorder).clean("el reporte va el jueves"),
            "El reporte va el jueves.",
        )

    def test_empty_text_never_runs_the_binary(self) -> None:
        recorder = Recorder(stdout=answer("x"))

        self.assertEqual(build(recorder).clean(""), "")
        self.assertEqual(recorder.commands, [])

    def test_the_shared_instruction_is_what_is_sent(self) -> None:
        """Two providers compared on one corpus must be told the same thing.

        `cleaners/prompt.py` owns that text, so the adapter may not paraphrase it.
        """
        recorder = Recorder(stdout=answer("Hola."))

        build(recorder).clean("hola", language_hint="es")

        sent = json.loads(recorder.inputs[0])
        self.assertEqual(sent["instructions"], CONSERVATIVE_SYSTEM_PROMPT)
        self.assertIn("Language hint: es", sent["prompt"])
        self.assertIn("hola", sent["prompt"])

    def test_the_mode_selects_the_instruction(self) -> None:
        recorder = Recorder(stdout=answer("The report is due Thursday."))

        build(recorder, mode="translate").clean("el reporte va el jueves")

        sent = json.loads(recorder.inputs[0])
        self.assertEqual(sent["instructions"], TRANSLATE_EN_SYSTEM_PROMPT)

    def test_an_unavailable_model_is_reported_as_such(self) -> None:
        """Status 2 is not a provider error; it says this Mac cannot run the model."""
        recorder = Recorder(
            stderr="Apple's on-device model is unavailable on this Mac: deviceNotEligible.",
            returncode=2,
        )

        with self.assertRaises(CleanupError) as raised:
            build(recorder).clean("hola")

        self.assertIn("unavailable on this Mac", str(raised.exception))

    def test_a_failure_carries_the_reason(self) -> None:
        recorder = Recorder(stderr="Apple's on-device model failed: out of memory.", returncode=1)

        with self.assertRaises(CleanupError) as raised:
            build(recorder).clean("hola")

        self.assertIn("out of memory", str(raised.exception))

    def test_an_unparsable_answer_is_refused(self) -> None:
        recorder = Recorder(stdout="not json at all")

        with self.assertRaises(CleanupError):
            build(recorder).clean("hola")

    def test_empty_cleaned_text_is_refused(self) -> None:
        recorder = Recorder(stdout=answer("   "))

        with self.assertRaises(CleanupError):
            build(recorder).clean("hola")

    def test_a_missing_binary_names_itself(self) -> None:
        cleaner = AppleCleaner(binary="/nowhere/voiceflow-apple-cleaner", runner=Recorder())

        with self.assertRaises(CleanupError) as raised:
            cleaner.clean("hola")

        self.assertIn("was not found", str(raised.exception))

    def test_a_timeout_is_reported_without_a_traceback(self) -> None:
        def slow(command, **kwargs):
            raise subprocess.TimeoutExpired(command, 60.0)

        cleaner = AppleCleaner(binary="/usr/bin/true", runner=slow)

        with self.assertRaises(CleanupError) as raised:
            cleaner.clean("hola")

        self.assertIn("did not finish", str(raised.exception))


class AppleRegistrationTests(unittest.TestCase):
    def test_the_factory_builds_it_by_name(self) -> None:
        cleaner = build_cleaner("apple", mode="meeting")

        self.assertIsInstance(cleaner, AppleCleaner)
        self.assertEqual(cleaner.name, "apple")
        self.assertEqual(cleaner.mode, "meeting")

    def test_it_is_not_a_cloud_cleaner(self) -> None:
        """Nothing leaves the device, so no caller may warn or gate on it as cloud."""
        from sanbluedot_voiceflow.cleaners import CLEANER_NAMES, CLOUD_CLEANER_NAMES

        self.assertIn("apple", CLEANER_NAMES)
        self.assertNotIn("apple", CLOUD_CLEANER_NAMES)


if __name__ == "__main__":
    unittest.main()
