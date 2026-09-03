"""Voice snippets and macro expansions.

Spoken triggers (e.g. "mi LinkedIn", "firma formal", "mi Calendly") expand instantly
into full multi-line text blocks, URLs, or structured templates.
Stored locally in JSON with versioned schema and atomic writes.
"""

import json
import re
import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from .errors import VoiceFlowError
from .memory import (
    DEFAULT_DIRECTORY,
    exclusive_file_lock,
    quarantine_file,
    read_json_or_quarantine,
    schema_version_is_supported,
    write_json_atomically,
)

SCHEMA_VERSION = 1
DEFAULT_SNIPPETS = DEFAULT_DIRECTORY / "snippets.local.json"


@dataclass(frozen=True)
class Snippet:
    trigger: str
    expansion: str
    description: str | None = None

    def to_dict(self) -> dict[str, Any]:
        data: dict[str, Any] = {
            "trigger": self.trigger,
            "expansion": self.expansion,
        }
        if self.description:
            data["description"] = self.description
        return data

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Snippet":
        if not isinstance(data, dict):
            raise ValueError("Snippet payload must be a dictionary.")
        trigger = data.get("trigger")
        expansion = data.get("expansion")
        if not isinstance(trigger, str) or not isinstance(expansion, str) or not trigger.strip() or not expansion.strip():
            raise ValueError("Snippet trigger and expansion must be non-empty strings.")
        return cls(
            trigger=trigger.strip(),
            expansion=expansion.strip(),
            description=data.get("description") if isinstance(data.get("description"), str) else None,
        )


def evaluate_macro_expansion(
    template: str,
    now: datetime | None = None,
    app_name: str | None = None,
) -> str:
    """Resolve dynamic template variables like {date}, {time}, {uuid}, and {app}.

    `{day}` is the day of the month, matching `{month}` and `{year}`. It returned the
    weekday name through `%A`, which ignores the speaker's language and writes
    "Thursday" into a Spanish sentence; a localized weekday is a separate decision and
    a numeric day is the one the neighbouring macros already imply.

    `{app}` stays literal when the caller does not know the frontmost application, so an
    unresolved macro is visible in the text rather than silently blank.
    """
    current = now or datetime.now()
    resolved = template
    if "{date}" in resolved:
        resolved = resolved.replace("{date}", current.strftime("%Y-%m-%d"))
    if "{time}" in resolved:
        resolved = resolved.replace("{time}", current.strftime("%H:%M"))
    if "{datetime}" in resolved:
        resolved = resolved.replace("{datetime}", current.strftime("%Y-%m-%d %H:%M"))
    if "{year}" in resolved:
        resolved = resolved.replace("{year}", current.strftime("%Y"))
    if "{month}" in resolved:
        resolved = resolved.replace("{month}", current.strftime("%m"))
    if "{day}" in resolved:
        resolved = resolved.replace("{day}", current.strftime("%d"))
    if "{uuid}" in resolved:
        resolved = resolved.replace("{uuid}", str(uuid.uuid4()))
    if app_name is not None and "{app}" in resolved:
        resolved = resolved.replace("{app}", app_name)
    return resolved


def expand_snippets(
    text: str,
    snippets: Sequence[Snippet],
    now: datetime | None = None,
    app_name: str | None = None,
) -> str:
    """Expand matching snippet triggers within text in a single non-cascading scan.

    A single regex scan prevents multi-pass cascading substitution where the expansion
    of one snippet accidentally triggers a second snippet. Using a lambda function for
    substitution ensures backslashes (e.g. Windows paths, LaTeX) and group references
    in snippet expansions are treated as pure literal strings.
    """
    if not text.strip() or not snippets:
        return text

    usable = [s for s in snippets if s.trigger.strip()]
    if not usable:
        return text

    # Sort longest triggers first so specific multi-word phrases match before substrings
    ordered = sorted(usable, key=lambda s: len(s.trigger.strip()), reverse=True)
    by_key = {s.trigger.strip().casefold(): s.expansion for s in ordered}

    pattern = re.compile(
        "|".join(rf"(?<!\w){re.escape(s.trigger.strip())}(?!\w)" for s in ordered),
        re.IGNORECASE | re.UNICODE,
    )

    def replace(match: re.Match[str]) -> str:
        matched = match.group(0)
        intended = by_key.get(matched.casefold())
        if intended is None:
            collapsed = " ".join(matched.split()).casefold()
            intended = by_key.get(collapsed)
        if intended is None:
            return matched
        return evaluate_macro_expansion(intended, now=now, app_name=app_name)

    return pattern.sub(replace, text)


class SnippetStore:
    """Thread-safe and process-safe store for voice snippets."""

    def __init__(self, path: Path = DEFAULT_SNIPPETS) -> None:
        self.path = path

    def load(self) -> list[Snippet]:
        if not self.path.is_file():
            return []

        payload = read_json_or_quarantine(self.path, "The snippet store")
        if payload is None:
            return []

        if not schema_version_is_supported(payload, self.path, "The snippet store"):
            return []

        raw_items = payload.get("snippets")
        if not isinstance(raw_items, list):
            quarantine_file(self.path, "The snippet store", "the snippets field is not a list")
            return []

        snippets: list[Snippet] = []
        for item in raw_items:
            try:
                snippets.append(Snippet.from_dict(item))
            except (ValueError, TypeError, KeyError):
                continue
        return snippets

    def add(self, trigger: str, expansion: str, description: str | None = None) -> Snippet:
        trig = trigger.strip()
        exp = expansion.strip()
        if not trig or not exp:
            raise VoiceFlowError("Snippet trigger and expansion cannot be empty.")

        snippet = Snippet(trigger=trig, expansion=exp, description=description.strip() if description else None)

        with exclusive_file_lock(self.path):
            existing = [s for s in self.load() if s.trigger.strip().casefold() != trig.casefold()]
            existing.append(snippet)
            payload = {
                "schema_version": SCHEMA_VERSION,
                "snippets": [s.to_dict() for s in existing],
            }
            write_json_atomically(self.path, payload)

        return snippet

    def delete(self, trigger: str) -> bool:
        trig = trigger.strip().casefold()
        if not trig:
            return False

        with exclusive_file_lock(self.path):
            current = self.load()
            filtered = [s for s in current if s.trigger.strip().casefold() != trig]
            if len(filtered) == len(current):
                return False

            payload = {
                "schema_version": SCHEMA_VERSION,
                "snippets": [s.to_dict() for s in filtered],
            }
            write_json_atomically(self.path, payload)
            return True

    def clear(self) -> None:
        with exclusive_file_lock(self.path):
            payload = {
                "schema_version": SCHEMA_VERSION,
                "snippets": [],
            }
            write_json_atomically(self.path, payload)

    def export_json(self, dest: Path) -> int:
        snippets = self.load()
        payload = {
            "schema_version": SCHEMA_VERSION,
            "snippets": [s.to_dict() for s in snippets],
        }
        write_json_atomically(dest, payload)
        return len(snippets)

    def import_json(self, src: Path) -> int:
        if not src.is_file():
            raise VoiceFlowError(f"Snippet import file not found: {src}")

        try:
            payload = json.loads(src.read_text(encoding="utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("The top-level JSON value is not an object.")
            raw_items = payload.get("snippets")
            if not isinstance(raw_items, list):
                raise ValueError("Payload missing snippets list.")
        except Exception as exc:
            raise VoiceFlowError(f"Failed to read snippet import file: {exc}") from exc

        with exclusive_file_lock(self.path):
            existing_map = {s.trigger.strip().casefold(): s for s in self.load()}
            count = 0
            for item in raw_items:
                try:
                    snip = Snippet.from_dict(item)
                    existing_map[snip.trigger.strip().casefold()] = snip
                    count += 1
                except Exception:
                    continue

            payload_to_write = {
                "schema_version": SCHEMA_VERSION,
                "snippets": [s.to_dict() for s in existing_map.values()],
            }
            write_json_atomically(self.path, payload_to_write)
        return count
