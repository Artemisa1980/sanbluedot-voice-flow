import platform
import subprocess
from collections.abc import Callable

from .errors import OutputError


Runner = Callable[..., subprocess.CompletedProcess[str]]


def copy_text(
    text: str,
    *,
    system: str | None = None,
    runner: Runner = subprocess.run,
) -> None:
    current_system = system or platform.system()
    if current_system == "Darwin":
        command = ["pbcopy"]
    elif current_system == "Windows":
        command = ["clip.exe"]
    else:
        raise OutputError(f"Clipboard output is not supported on {current_system}.")

    try:
        runner(command, input=text, text=True, check=True, capture_output=True)
    except (FileNotFoundError, UnicodeError, subprocess.CalledProcessError) as exc:
        raise OutputError(f"Clipboard command failed on {current_system}.") from exc

