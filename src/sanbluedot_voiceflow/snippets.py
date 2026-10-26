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
    preserve_skipped,
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
        # One fresh value per occurrence, as README promises; `replace` gave every
        # `{uuid}` the same one (D-159).
        resolved = re.sub(r"\{uuid\}", lambda _: str(uuid.uuid4()), resolved)
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
    by_key = {" ".join(s.trigger.split()).casefold(): s.expansion for s in ordered}

    # Words joined by any whitespace, so a trigger spoken or stored with a double space
    # or a tab still fires (D-161).
    pattern = re.compile(
        "|".join(
            r"(?<!\w)" + r"\s+".join(re.escape(word) for word in s.trigger.split()) + r"(?!\w)"
            for s in ordered
        ),
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
        skipped = 0
        for item in raw_items:
            try:
                snippets.append(Snippet.from_dict(item))
            except (ValueError, TypeError, KeyError):
                skipped += 1
        preserve_skipped(self.path, "The snippet store", skipped)
        return snippets

    def add(self, trigger: str, expansion: str, description: str | None = None) -> Snippet:
        trig = " ".join(trigger.split())
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

    def import_json(self, src: Path) -> "ImportReport":
        if not src.is_file():
            raise VoiceFlowError(f"Snippet import file not found: {src}")

        try:
            payload = json.loads(src.read_text(encoding="utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("The top-level JSON value is not an object.")
            raw_items = payload.get("snippets")
            if not isinstance(raw_items, list):
                raise ValueError("Payload missing snippets list.")
            # An unknown version is refused rather than read as this one (D-160).
            version = payload.get("schema_version", SCHEMA_VERSION)
            if type(version) is not int or version != SCHEMA_VERSION:
                raise ValueError(f"unsupported schema version: {version!r}")
        except Exception as exc:
            raise VoiceFlowError(f"Failed to read snippet import file: {exc}") from exc

        added = replaced = skipped = 0
        with exclusive_file_lock(self.path):
            existing_map = {s.trigger.strip().casefold(): s for s in self.load()}
            for item in raw_items:
                try:
                    snip = Snippet.from_dict(item)
                except Exception:
                    skipped += 1
                    continue
                key = " ".join(snip.trigger.split()).casefold()
                if key in existing_map:
                    replaced += 1
                else:
                    added += 1
                existing_map[key] = snip

            payload_to_write = {
                "schema_version": SCHEMA_VERSION,
                "snippets": [s.to_dict() for s in existing_map.values()],
            }
            write_json_atomically(self.path, payload_to_write)
        return ImportReport(added=added, replaced=replaced, skipped=skipped)


@dataclass(frozen=True)
class ImportReport:
    """What an import did, entry by entry: it used to report one count (D-160)."""

    added: int
    replaced: int
    skipped: int

    @property
    def imported(self) -> int:
        return self.added + self.replaced
