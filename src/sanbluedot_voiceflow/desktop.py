"""Local desktop memory bridge. Payloads arrive on stdin, never in process arguments."""
import contextlib
import io
import json
import sys
from dataclasses import asdict
from pathlib import Path

from .doctor import ollama_status
from .memory import DEFAULT_DIRECTORY, CorrectionStore, correction_needs_global_confirmation, load_vocabulary
from .snippets import SnippetStore


def dispatch(request: dict, directory: Path = DEFAULT_DIRECTORY) -> dict:
    """Expose explicit memory operations, using the engine's existing versioned stores."""
    if not isinstance(request, dict):
        raise ValueError("Expected an action object.")
    action = request.get("action")
    # Readiness is answered before any personal store is opened: asking whether a local
    # service is up is not a reason to read the owner's vocabulary or corrections.
    if action == "provider_status":
        provider = request.get("provider")
        if provider != "ollama":
            raise ValueError("Only the local Ollama route can be checked from here.")
        model = request.get("model")
        if model is not None and (not isinstance(model, str) or not model.strip() or len(model) > 200):
            raise ValueError("model must be a name of at most 200 characters.")
        url = request.get("url") or "http://127.0.0.1:11434"
        if not isinstance(url, str) or not url.startswith(("http://127.0.0.1", "http://localhost")):
            raise ValueError("The local cleanup endpoint must stay on this machine.")
        return ollama_status(url, model.strip() if isinstance(model, str) else None)
    snippets = SnippetStore(directory / "snippets.local.json")
    corrections = CorrectionStore(directory / "corrections.local.json")

    def required(name):
        value = request.get(name)
        if not isinstance(value, str) or not value.strip() or len(value) > 16000 or "\0" in value:
            raise ValueError(f"{name} must contain between 1 and 16000 characters, without NUL.")
        return value.strip()

    warnings = io.StringIO()
    with contextlib.redirect_stderr(warnings):
        if action == "snippet_save":
            description = request.get("description")
            if description is not None and (not isinstance(description, str) or len(description) > 16000 or "\0" in description):
                raise ValueError("description must contain at most 16000 characters, without NUL.")
            snippets.add(required("trigger"), required("expansion"), description=description.strip() or None if description is not None else None)
        elif action == "snippet_delete":
            snippets.delete(required("trigger"))
        elif action == "correction_save":
            heard, intended = required("heard"), required("intended")
            if correction_needs_global_confirmation(heard) and request.get("allow_global") is not True:
                raise ValueError("Confirm that this single-word correction applies everywhere.")
            corrections.add(heard, intended)
        elif action == "correction_delete":
            corrections.remove(required("heard"))
        elif action != "read":
            raise ValueError("Unsupported memory action.")
        result = {
            "directory": str(directory),
            "vocabulary": load_vocabulary(directory / "vocabulary.local.txt"),
            "corrections": [asdict(item) for item in corrections.load()],
            "snippets": [item.to_dict() for item in snippets.load()],
        }
    result["warning"] = warnings.getvalue().strip() or None
    return result


def main() -> int:
    try:
        text = sys.stdin.read(65537)
        if len(text) > 65536:
            raise ValueError("Memory request is too large.")
        print(json.dumps(dispatch(json.loads(text)), ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
