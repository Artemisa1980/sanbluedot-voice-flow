import subprocess
import unittest

from sanbluedot_voiceflow.credentials import (
    delete_api_key,
    describe,
    environment_variable,
    read_api_key,
    store_api_key_interactively,
)
from sanbluedot_voiceflow.errors import VoiceFlowError


class FakeRunner:
    def __init__(self, returncode: int = 0, stdout: str = "") -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.commands: list[list[str]] = []

    def __call__(self, command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
        self.commands.append(command)
        return subprocess.CompletedProcess(command, self.returncode, self.stdout, "")


class EnvironmentNameTests(unittest.TestCase):
    def test_the_variable_is_derived_from_the_provider(self) -> None:
        self.assertEqual(environment_variable("gemini"), "VOICEFLOW_GEMINI_API_KEY")

    def test_a_dash_becomes_an_underscore(self) -> None:
        self.assertEqual(
            environment_variable("open-router"), "VOICEFLOW_OPEN_ROUTER_API_KEY"
        )

    def test_a_provider_name_that_could_pass_as_a_flag_is_refused(self) -> None:
        for hostile in ("-w", "../gemini", "gemini key", "", "GEMINI"):
            with self.assertRaises(VoiceFlowError):
                environment_variable(hostile)


class ReadTests(unittest.TestCase):
    def test_the_injected_environment_is_preferred_over_the_keychain(self) -> None:
        runner = FakeRunner(stdout="keychain-key")

        key = read_api_key(
            "gemini",
            environment={"VOICEFLOW_GEMINI_API_KEY": "environment-key"},
            runner=runner,
        )

        self.assertEqual(key, "environment-key")
        self.assertEqual(runner.commands, [])

    def test_the_keychain_answers_when_the_environment_is_empty(self) -> None:
        runner = FakeRunner(stdout="keychain-key\n")

        key = read_api_key("gemini", environment={}, runner=runner)

        self.assertEqual(key, "keychain-key")
        self.assertIn("find-generic-password", runner.commands[0])

    def test_the_app_can_disable_the_terminal_keychain_fallback(self) -> None:
        runner = FakeRunner(stdout="keychain-key")

        key = read_api_key(
            "gemini",
            environment={"VOICEFLOW_DISABLE_KEYCHAIN_FALLBACK": "1"},
            runner=runner,
        )

        self.assertIsNone(key)
        self.assertEqual(runner.commands, [])

    def test_a_blank_environment_value_is_not_a_key(self) -> None:
        runner = FakeRunner(returncode=44, stdout="")

        key = read_api_key(
            "gemini",
            environment={"VOICEFLOW_GEMINI_API_KEY": "   "},
            runner=runner,
        )

        self.assertIsNone(key)

    def test_a_missing_keychain_item_reads_as_no_key_rather_than_an_error(self) -> None:
        runner = FakeRunner(returncode=44, stdout="")

        self.assertIsNone(read_api_key("gemini", environment={}, runner=runner))

    def test_an_unreachable_keychain_reads_as_no_key(self) -> None:
        def runner(_command: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
            raise OSError("keychain unavailable")

        self.assertIsNone(read_api_key("gemini", environment={}, runner=runner))


class StoreTests(unittest.TestCase):
    def test_the_key_is_never_passed_as_an_argument(self) -> None:
        runner = FakeRunner()

        store_api_key_interactively("gemini", runner=runner)

        command = runner.commands[0]
        self.assertEqual(command[-1], "-w")
        self.assertIn("add-generic-password", command)

    def test_a_refused_write_is_reported(self) -> None:
        with self.assertRaises(VoiceFlowError):
            store_api_key_interactively("gemini", runner=FakeRunner(returncode=1))


class DeleteTests(unittest.TestCase):
    def test_removing_an_absent_key_reports_false_without_raising(self) -> None:
        self.assertFalse(delete_api_key("gemini", runner=FakeRunner(returncode=44)))

    def test_removing_a_stored_key_reports_true(self) -> None:
        self.assertTrue(delete_api_key("gemini", runner=FakeRunner()))

    def test_a_keychain_deletion_failure_is_not_reported_as_absence(self) -> None:
        with self.assertRaises(VoiceFlowError) as raised:
            delete_api_key("gemini", runner=FakeRunner(returncode=1))

        self.assertIn("not removed", str(raised.exception))


class DescribeTests(unittest.TestCase):
    def test_a_stored_key_is_described_without_revealing_it(self) -> None:
        secret = "not-a-real-key-fixture"

        description = describe(
            "gemini",
            environment={"VOICEFLOW_GEMINI_API_KEY": secret},
            runner=FakeRunner(),
        )

        self.assertEqual(description, "configured")
        self.assertNotIn(secret, description)

    def test_an_absent_key_is_named_as_absent(self) -> None:
        self.assertEqual(
            describe("gemini", environment={}, runner=FakeRunner(returncode=44)),
            "no key stored",
        )


if __name__ == "__main__":
    unittest.main()
