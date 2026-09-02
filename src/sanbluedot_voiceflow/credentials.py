"""Provider credentials, held by the operating system rather than by this project.

R7 keeps secrets out of source files, Markdown, logs, test fixtures and personal-memory
files. A key therefore lives in one place only: the macOS keychain. Two readers need it
and they reach it differently, so both routes are supported here.

The macOS app owns the keychain item through the Security framework and passes the key
to the engine in the child process environment, which avoids a keychain access prompt on
every dictation. A terminal run has no app to do that, so it falls back to the `security`
command against the same item. Neither route writes the key anywhere.
"""

import os
import re
import subprocess
from collections.abc import Callable, Mapping

from .errors import VoiceFlowError


Runner = Callable[..., subprocess.CompletedProcess[str]]

KEYCHAIN_SERVICE = "sanblue.voiceflow"
DISABLE_KEYCHAIN_FALLBACK_VARIABLE = "VOICEFLOW_DISABLE_KEYCHAIN_FALLBACK"
_PROVIDER = re.compile(r"^[a-z][a-z0-9-]{0,31}$")


def _checked(provider: str) -> str:
    """Reject a provider name that could reach the keychain as an option or flag."""
    if not _PROVIDER.match(provider):
        raise VoiceFlowError(f"Unsupported provider name: {provider!r}")
    return provider


def environment_variable(provider: str) -> str:
    return f"VOICEFLOW_{_checked(provider).upper().replace('-', '_')}_API_KEY"


def read_api_key(
    provider: str,
    *,
    environment: Mapping[str, str] | None = None,
    runner: Runner = subprocess.run,
) -> str | None:
    """Return the provider key, or None when no key is configured.

    The environment is read first because the app injects it there deliberately. A
    keychain lookup that fails for any reason is treated as an absent key: a missing
    credential is an ordinary configured state, never a crash mid-dictation.
    """
    provider = _checked(provider)
    source = os.environ if environment is None else environment
    from_environment = source.get(environment_variable(provider), "").strip()
    if from_environment:
        return from_environment
    if source.get(DISABLE_KEYCHAIN_FALLBACK_VARIABLE, "").strip() == "1":
        return None

    try:
        completed = runner(
            [
                "/usr/bin/security",
                "find-generic-password",
                "-s",
                KEYCHAIN_SERVICE,
                "-a",
                provider,
                "-w",
            ],
            capture_output=True,
            text=True,
            timeout=10.0,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if getattr(completed, "returncode", 1) != 0:
        return None
    key = (getattr(completed, "stdout", "") or "").strip()
    return key or None


def store_api_key_interactively(
    provider: str,
    *,
    runner: Runner = subprocess.run,
) -> None:
    """Hand the prompt to the `security` command instead of carrying the key.

    `-w` is passed last and with no value, which is the documented way to be prompted.
    A key given as an argument would be visible in the process list and in shell
    history, so this function never accepts one.
    """
    provider = _checked(provider)
    try:
        completed = runner(
            [
                "/usr/bin/security",
                "add-generic-password",
                "-s",
                KEYCHAIN_SERVICE,
                "-a",
                provider,
                "-U",
                "-l",
                f"sanblueᵈᵒᵗ VoiceFlow — {provider}",
                "-w",
            ],
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise VoiceFlowError(f"The keychain could not be reached: {exc}") from exc
    if getattr(completed, "returncode", 1) != 0:
        raise VoiceFlowError(f"The {provider} key was not stored.")


def delete_api_key(provider: str, *, runner: Runner = subprocess.run) -> bool:
    """Remove the stored key; distinguish absence from a failed privacy action."""
    provider = _checked(provider)
    try:
        completed = runner(
            [
                "/usr/bin/security",
                "delete-generic-password",
                "-s",
                KEYCHAIN_SERVICE,
                "-a",
                provider,
            ],
            capture_output=True,
            text=True,
            timeout=10.0,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise VoiceFlowError(f"The keychain could not be reached: {exc}") from exc
    returncode = getattr(completed, "returncode", 1)
    if returncode == 0:
        return True
    # The macOS `security` tool forwards errSecItemNotFound as exit status 44.
    if returncode == 44:
        return False
    raise VoiceFlowError(
        f"The {provider} key was not removed; the keychain refused the request "
        f"(status {returncode})."
    )


def describe(
    provider: str,
    *,
    environment: Mapping[str, str] | None = None,
    runner: Runner = subprocess.run,
) -> str:
    """Say whether a key is configured, without revealing any part of it."""
    key = read_api_key(provider, environment=environment, runner=runner)
    return "configured" if key else "no key stored"
