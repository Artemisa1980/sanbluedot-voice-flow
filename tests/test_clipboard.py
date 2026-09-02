import subprocess
import unittest

from sanbluedot_voiceflow.clipboard import copy_text
from sanbluedot_voiceflow.errors import OutputError


class ClipboardTests(unittest.TestCase):
    def test_mac_uses_pbcopy(self) -> None:
        calls: list[tuple[list[str], str]] = []

        def runner(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
            calls.append((command, kwargs["input"]))  # type: ignore[index]
            return subprocess.CompletedProcess(command, 0, "", "")

        copy_text("hello", system="Darwin", runner=runner)

        self.assertEqual(calls, [(["pbcopy"], "hello")])

    def test_unencodable_text_becomes_an_output_error(self) -> None:
        def runner(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
            raise UnicodeEncodeError("charmap", "ó", 0, 1, "unmapped character")

        with self.assertRaises(OutputError):
            copy_text("acción", system="Windows", runner=runner)

    def test_unknown_platform_is_rejected(self) -> None:
        with self.assertRaises(OutputError):
            copy_text("hello", system="Plan9")


if __name__ == "__main__":
    unittest.main()
