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


class ClipboardFailureTests(unittest.TestCase):
    """D-158: a permission error or a hang is a reported failure, not a traceback."""

    def test_os_errors_and_timeouts_are_reported(self) -> None:
        import subprocess
        from sanbluedot_voiceflow.clipboard import copy_text
        from sanbluedot_voiceflow.errors import OutputError

        for error in (PermissionError("denied"), subprocess.TimeoutExpired("pbcopy", 10)):
            def runner(*_a, **kwargs):
                self.assertEqual(kwargs.get("timeout"), 10)
                raise error
            with self.subTest(error=type(error).__name__), self.assertRaises(OutputError):
                copy_text("hola", system="Darwin", runner=runner)
