"""Gemini cleanup adapter: transcript text only, never audio, never on by default.

Request and response shapes follow the official Google Gemini API (Generative Language API)
v1beta documentation for generateContent with structured JSON schema output:
`POST /v1beta/models/{model}:generateContent` with the key in an `x-goog-api-key` header,
systemInstruction, and generationConfig setting responseMimeType to application/json and
responseSchema. The endpoint base and model identifier are constructor arguments precisely
because they are Google's to change and this project's to configure, not architecture.

Nothing here reaches the network unless the caller selects this cleaner and a key is
stored. Every failure raises `CleanupError`, which the pipeline converts into a fallback
to the deterministic personalized transcript, so a provider outage costs the speaker
nothing but the cleanup.
"""

import errno
import json
import socket
import sys
import time
from collections.abc import Callable
from typing import Any, Sequence
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from ..credentials import read_api_key
from ..errors import CleanupError
from .prompt import (
    CLEANED_TEXT_SCHEMA,
    CONSERVATIVE_SYSTEM_PROMPT,
    FIX_SYSTEM_PROMPT,
    MEETING_NOTES_SYSTEM_PROMPT,
    TRANSLATE_EN_SYSTEM_PROMPT,
    output_token_budget,
)


Opener = Callable[..., Any]
Announcer = Callable[[str], None]

PROVIDER = "gemini"
DEFAULT_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
# Interleaved measurements on 2026-08-31, same minutes, same request shape, one synthetic
# Spanish sentence, identical output quality on cleanup, translation and meeting notes:
#
#   gemini-3.5-flash   5/6 delivered   2.3s median
#   gemini-3.6-flash   4/6 delivered  14.3s median
#   gemini-3.7-flash   3/6 delivered  12.5s median
#
# The default is the model that answers, not the highest version. 3.7 does return
# inference — the earlier "no response" reading was the old 20-second ceiling cancelling
# replies as they arrived — but it is the least available of the three. Change this
# against a fresh measurement of the candidates, never from the version number.
DEFAULT_MODEL = "gemini-3.5-flash"

# Ordered by measured delivery, not by version. A 503 is Google reporting capacity on one
# model, so the next model here is tried inside the same timeout budget rather than
# dropping the speaker to the unpunctuated transcript. Ordering by version instead would
# send a fallback from 3.5 straight to the least available model. Every model here
# produced equivalent output on the 2026-08-31 samples, so moving down the chain costs
# quality nothing measurable. A model reaches this list only after it is measured.
MODEL_CHAIN = ("gemini-3.5-flash", "gemini-3.6-flash", "gemini-3.7-flash")


def model_chain(preferred: str) -> tuple[str, ...]:
    """The preferred model first, then the remaining known models in order."""
    return (preferred,) + tuple(m for m in MODEL_CHAIN if m != preferred)

# The same measurement: successful replies took 5.4 to 34.6 seconds, so the previous
# 20-second ceiling cancelled calls that were about to succeed and made a healthy model
# look unreachable. The budget is wider than the slowest observed reply.
DEFAULT_TIMEOUT_SECONDS = 45.0

# The same measurement returned HTTP 503 on 6 of 9 calls to 3.7 and 2 of 6 to 3.6.
# A 503 is Google reporting transient capacity, not a rejected request, and the retry
# costs one extra call against a failure that would otherwise drop the speaker straight
# to the unpunctuated transcript. The retry shares the one timeout budget, so recovery
# never doubles the time a speaker waits before the fallback arrives.
RETRYABLE_STATUS = frozenset({500, 502, 503, 504})
RETRIES_ON_TRANSIENT_STATUS = 1
RETRY_BACKOFF_SECONDS = 1.5
MINIMUM_RETRY_BUDGET_SECONDS = 5.0

# No single model may spend the whole budget. Measured live: a busy `gemini-3.7-flash`
# consumed all 45 seconds and timed out, so `gemini-3.5-flash` — which answered the same
# prompt in 5 seconds — was never reached. Each model therefore gets an equal share.
#
# The share is derived from the chain actually being walked, not fixed to today's three
# models: `--gemini-model` accepts any identifier, so an unlisted model produces a longer
# chain, and a hardcoded slice would spend the budget before reaching a healthy model.
PER_MODEL_TIMEOUT_SECONDS = 15.0


def per_model_slice(total_seconds: float, chain_length: int) -> float:
    """An equal share of the budget, never below the floor a reply needs to arrive."""
    if chain_length <= 1:
        return total_seconds
    return max(MINIMUM_RETRY_BUDGET_SECONDS, total_seconds / chain_length)


CONTACT_AT_CAPACITY = "capacity"
CONTACT_TIMED_OUT = "timed out"
# One attempt died on a connection that is still there. Reported apart from a timeout
# because the clock is not what ran out, and apart from an unreachable host because the
# next model is still worth trying.
CONTACT_DROPPED = "dropped"

_ONE_MODEL = {
    CONTACT_AT_CAPACITY: "Gemini is at capacity ({names}).",
    CONTACT_TIMED_OUT: "Gemini ran out of the time budget ({names}).",
    CONTACT_DROPPED: "Gemini dropped the connection ({names}).",
}
_EVERY_MODEL = {
    CONTACT_AT_CAPACITY: "Every Gemini model contacted is at capacity: {names}.",
    CONTACT_TIMED_OUT: (
        "Every Gemini model contacted ran out of the time budget: {names}."
    ),
    CONTACT_DROPPED: "Every Gemini model contacted dropped the connection: {names}.",
}
_PER_MODEL = {
    CONTACT_AT_CAPACITY: "{model} was at capacity",
    CONTACT_TIMED_OUT: "{model} ran out of the time budget",
    CONTACT_DROPPED: "{model} dropped the connection",
}


def describe_chain_failure(
    contacted: Sequence[tuple[str, str]],
    skipped: Sequence[str] = (),
) -> str:
    """Say what happened to each model that was actually contacted.

    The message used to list the whole chain, so a model the budget check skipped before
    any request left this machine was still reported as being at capacity. That is a
    claim about Google's availability that this code has no evidence for: nothing was
    ever sent. A skipped model is now named as skipped, and a model that ran out of its
    slice is named as slow rather than as busy.
    """
    if not contacted:
        if skipped:
            return (
                "No Gemini model was contacted before the time budget ran out: "
                f"{', '.join(skipped)}."
            )
        return "No Gemini model was contacted before the time budget ran out."

    reasons = {reason for _, reason in contacted}
    names = ", ".join(model for model, _ in contacted)
    if len(reasons) == 1:
        reason = next(iter(reasons))
        template = _ONE_MODEL[reason] if len(contacted) == 1 else _EVERY_MODEL[reason]
        detail = template.format(names=names)
    else:
        parts = "; ".join(
            _PER_MODEL[reason].format(model=model) for model, reason in contacted
        )
        detail = f"Gemini did not answer: {parts}."
    if skipped:
        detail += f" Not contacted, no budget left: {', '.join(skipped)}."
    return detail


def _announce_to_stderr(message: str) -> None:
    print(message, file=sys.stderr)


# This machine has no route to the provider: the name does not resolve, the connection is
# refused, or the network is down. Nothing was sent, so nothing can be said about any
# model's availability and the chain has nothing better to reach.
_UNREACHABLE_TYPES = (socket.gaierror, ConnectionRefusedError)
_UNREACHABLE_ERRNOS = frozenset({
    errno.ENETUNREACH,
    errno.EHOSTUNREACH,
    errno.ENETDOWN,
    errno.ECONNREFUSED,
})


def _is_unreachable(error: BaseException) -> bool:
    """Whether the provider could not be reached at all from this machine.

    `urlopen` reports a slow reply, a dropped connection and an unresolvable name through
    the same exception family, and they are not the same fact: the first two are about
    one attempt, the third is about the network here. Only the third makes the rest of
    the chain pointless, because every model behind it is just as unreachable.
    """
    for candidate in (error, getattr(error, "reason", None)):
        if isinstance(candidate, _UNREACHABLE_TYPES):
            return True
        if getattr(candidate, "errno", None) in _UNREACHABLE_ERRNOS:
            return True
    return False


def _contact_reason(error: BaseException) -> str:
    """Whether this attempt ran out of time or lost the connection it had."""
    for candidate in (error, getattr(error, "reason", None)):
        if isinstance(candidate, TimeoutError):
            return CONTACT_TIMED_OUT
    return CONTACT_DROPPED


class _ModelUnfinished(Exception):
    """One attempt did not deliver. Internal: it never leaves this module.

    `reason` separates the clock running out from the connection being lost, because the
    failure message names what happened to each model and the two are different facts.
    """

    def __init__(self, cause: Exception, reason: str = CONTACT_TIMED_OUT) -> None:
        super().__init__("model did not finish")
        self.cause = cause
        self.reason = reason


class _TransientProvider(Exception):
    """One model is at capacity. Internal: it never leaves this module.

    Kept separate from `CleanupError` so the chain can tell "this model is busy, try the
    next one" apart from "this request is wrong, stop", which must never be retried
    against another model.
    """

    def __init__(self, status: int, cause: Exception) -> None:
        super().__init__(f"transient provider status {status}")
        self.status = status
        self.cause = cause


class GeminiCleaner:
    """Conservative cleanup or translation through Gemini, announced before anything is sent."""

    name = PROVIDER

    def __init__(
        self,
        model: str = DEFAULT_MODEL,
        endpoint: str = DEFAULT_ENDPOINT,
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
        mode: str = "clean",
        opener: Opener = urlopen,
        announce: Announcer = _announce_to_stderr,
        api_key_reader: Callable[[str], str | None] = read_api_key,
        sleep: Callable[[float], None] = time.sleep,
        monotonic: Callable[[], float] = time.monotonic,
        fallback: bool = True,
    ) -> None:
        self.model = model
        self.endpoint = endpoint
        self.timeout_seconds = timeout_seconds
        self.mode = mode
        self.fallback = fallback
        # Which model actually answered. The interface reports the model that produced
        # the text, not the one that was asked for, so a silent downgrade is visible.
        self.answered_with: str | None = None
        self._opener = opener
        self._announce = announce
        self._read_api_key = api_key_reader
        self._sleep = sleep
        self._monotonic = monotonic

    def _build_url(self, model: str) -> str:
        if "{model}" in self.endpoint:
            return self.endpoint.format(model=model)
        if ":generateContent" in self.endpoint or ":streamGenerateContent" in self.endpoint:
            return self.endpoint
        return f"{self.endpoint.rstrip('/')}/models/{model}:generateContent"

    def clean(
        self,
        text: str,
        language_hint: str | None = None,
        mode: str | None = None,
    ) -> str:
        # `mode` overrides the constructed mode for this call only. The pipeline uses it
        # to run a `clean` dictation that carries a spoken take-back as a fix.
        active_mode = mode or self.mode
        if not text:
            return text

        api_key = self._read_api_key(PROVIDER)
        if not api_key:
            raise CleanupError(
                "No Gemini API key is configured. Store one with "
                "`vf provider set-key gemini`, or keep using local cleanup."
            )

        if active_mode == "translate":
            mode_label = " [mode: translate (ES -> EN)]"
            system_instruction = TRANSLATE_EN_SYSTEM_PROMPT
        elif active_mode == "meeting":
            mode_label = " [mode: meeting notes & action items]"
            system_instruction = MEETING_NOTES_SYSTEM_PROMPT
        elif active_mode == "fix":
            mode_label = " [mode: fix self-corrections]"
            system_instruction = FIX_SYSTEM_PROMPT
        else:
            mode_label = ""
            system_instruction = CONSERVATIVE_SYSTEM_PROMPT

        chain = model_chain(self.model) if self.fallback else (self.model,)

        # Gate 4 requires the selected provider to be visible before transmission. The
        # notice is emitted by the adapter rather than by a caller, so no caller can
        # send the speaker's words silently by forgetting to print it. The whole chain is
        # named, because every model in it may receive the text.
        chain_label = "" if len(chain) == 1 else f", falling back to {', '.join(chain[1:])}"
        self._announce(
            f"Sending {len(text)} characters of transcript text to {PROVIDER} "
            f"({self.model}{chain_label}){mode_label}. No audio is sent."
        )

        payload = {
            "contents": [
                {
                    "parts": [
                        {
                            "text": (
                                f"Language hint: {language_hint or 'auto-detected'}\n\n"
                                f"Transcript:\n{text}"
                            )
                        }
                    ]
                }
            ],
            "systemInstruction": {
                "parts": [{"text": system_instruction}]
            },
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": CLEANED_TEXT_SCHEMA,
                "maxOutputTokens": output_token_budget(text),
            },
        }
        body = json.dumps(payload).encode("utf-8")
        headers = {"Content-Type": "application/json", "x-goog-api-key": api_key}

        self.answered_with = None
        deadline = self._monotonic() + self.timeout_seconds
        slice_seconds = per_model_slice(self.timeout_seconds, len(chain))
        last_error: Exception | None = None

        # What was actually sent, and to whom. The failure message is built from this
        # rather than from the chain, so it can never name a model nothing reached.
        contacted: list[tuple[str, str]] = []
        skipped: list[str] = []

        for index, model in enumerate(chain):
            if index and self._monotonic() >= deadline - MINIMUM_RETRY_BUDGET_SECONDS:
                # Too little budget left to be worth another model. Falling back exists
                # to save the cleanup, not to keep the speaker waiting past the point
                # where the deterministic transcript is the better answer.
                skipped = list(chain[index:])
                break
            # Announce only after the budget allows the attempt. Naming a model first
            # and then refusing to contact it is a promise the speaker can see broken.
            if index:
                self._announce(f"Trying {model}.")
            request = Request(
                self._build_url(model), data=body, headers=headers, method="POST"
            )
            # The last model may use whatever is left; the earlier ones may not starve it.
            is_last = index + 1 == len(chain)
            attempt_deadline = (
                deadline if is_last
                else min(deadline, self._monotonic() + slice_seconds)
            )
            try:
                raw = self._send(request, attempt_deadline, hard_deadline=deadline)
            except _ModelUnfinished as exc:
                # A model that ran out of its slice is busy, not broken. The next one
                # gets the remaining budget rather than the speaker getting nothing.
                last_error = exc.cause
                contacted.append((model, exc.reason))
                if is_last:
                    # The last model's timeout used to raise straight past the record of
                    # what this run contacted, so the speaker was told "Gemini request
                    # failed" and no model was named — not the one that just timed out,
                    # nor the ones that were busy before it.
                    raise CleanupError(
                        describe_chain_failure(contacted, skipped)
                    ) from exc.cause
                self._announce(
                    f"{model} ran out of its share of the time budget."
                    if exc.reason == CONTACT_TIMED_OUT
                    else f"{model} dropped the connection."
                )
                continue
            except _TransientProvider as exc:
                # Report only what happened. Naming the next model here would promise a
                # request the budget check at the top of the loop may refuse to make.
                last_error = exc.cause
                contacted.append((model, CONTACT_AT_CAPACITY))
                self._announce(f"{model} is at capacity ({exc.status}).")
                continue
            self.answered_with = model
            return _extract_cleaned_text(raw)

        if last_error is None:
            raise CleanupError("Gemini had no time left to answer.")
        raise CleanupError(describe_chain_failure(contacted, skipped)) from last_error

    def _send(self, request: Request, deadline: float, hard_deadline: float) -> str:
        """Post one model's request, retrying a transient status within the budget.

        A retry is safe because the request carries no side effect: it asks for cleanup
        of text the caller already holds. Only a retryable status is repeated, so a
        rejected key or a malformed request is never sent twice.

        `deadline` bounds the whole call across every model, not each attempt. A fast
        503 leaves almost the full budget for the next try, while a slow one leaves too
        little and the speaker falls back to the deterministic transcript instead of
        waiting through the entire chain.
        """
        retries_left = RETRIES_ON_TRANSIENT_STATUS
        while True:
            remaining = deadline - self._monotonic()
            try:
                with self._opener(request, timeout=max(remaining, 0.0)) as response:
                    return response.read().decode("utf-8")
            except HTTPError as exc:
                # The status is useful; the body can echo the request and is not logged.
                if exc.code not in RETRYABLE_STATUS:
                    raise CleanupError(
                        f"Gemini refused the request ({exc.code})."
                    ) from exc
                budget_after_backoff = (
                    deadline - self._monotonic() - RETRY_BACKOFF_SECONDS
                )
                if (
                    retries_left > 0
                    and budget_after_backoff >= MINIMUM_RETRY_BUDGET_SECONDS
                ):
                    retries_left -= 1
                    self._announce(
                        f"{PROVIDER} reported a temporary capacity error "
                        f"({exc.code}). Retrying once."
                    )
                    self._sleep(RETRY_BACKOFF_SECONDS)
                    continue
                raise _TransientProvider(exc.code, exc) from exc
            except (URLError, TimeoutError, OSError) as exc:
                if _is_unreachable(exc):
                    # No route to the provider. The chain exists to survive one busy
                    # model, and every model behind this one is just as unreachable, so
                    # walking it would spend the speaker's time to learn nothing.
                    raise CleanupError(
                        f"Gemini could not be reached from this machine: {exc}. "
                        "Nothing was sent, so this is the connection here rather than "
                        "the provider."
                    ) from exc
                if self._monotonic() < hard_deadline:
                    raise _ModelUnfinished(exc, _contact_reason(exc)) from exc
                raise CleanupError(f"Gemini request failed: {exc}") from exc


def _extract_cleaned_text(body: str) -> str:
    """Read the cleaned text out of one response, or say the response was unusable.

    Both documented paths are accepted, `candidates` first and legacy/fallback fields
    second, so variations in provider responses are safely handled.
    """
    try:
        parsed = json.loads(body)
    except json.JSONDecodeError as exc:
        raise CleanupError("Gemini returned an invalid response.") from exc
    if not isinstance(parsed, dict):
        raise CleanupError("Gemini returned an invalid response.")

    content = _text_from_candidates(parsed)
    if not isinstance(content, str) or not content.strip():
        content = parsed.get("output_text")
    if not isinstance(content, str) or not content.strip():
        content = _text_from_steps(parsed)
    if not isinstance(content, str) or not content.strip():
        raise CleanupError("Gemini returned empty text.")

    cleaned_raw = content.strip()
    if cleaned_raw.startswith("```"):
        import re
        cleaned_raw = re.sub(r"^```(?:json)?\s*", "", cleaned_raw)
        cleaned_raw = re.sub(r"\s*```$", "", cleaned_raw).strip()

    try:
        cleaned_text = json.loads(cleaned_raw)["cleaned_text"]
    except (json.JSONDecodeError, KeyError, TypeError) as exc:
        raise CleanupError("Gemini returned invalid cleanup JSON.") from exc
    if not isinstance(cleaned_text, str) or not cleaned_text.strip():
        raise CleanupError("Gemini returned empty cleaned text.")
    return cleaned_text.strip()


def _text_from_candidates(parsed: dict[str, Any]) -> str | None:
    candidates = parsed.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        return None
    for candidate in candidates:
        if not isinstance(candidate, dict):
            continue
        content = candidate.get("content")
        if not isinstance(content, dict):
            continue
        parts = content.get("parts")
        if not isinstance(parts, list):
            continue
        text_parts = [
            part["text"]
            for part in parts
            if isinstance(part, dict)
            and isinstance(part.get("text"), str)
            and not part.get("thought", False)
        ]
        if text_parts:
            return "".join(text_parts)
    return None


def _text_from_steps(parsed: dict[str, Any]) -> str | None:
    steps = parsed.get("steps")
    if not isinstance(steps, list):
        return None
    for step in reversed(steps):
        if not isinstance(step, dict):
            continue
        content = step.get("content", [])
        if not isinstance(content, list):
            continue
        text_parts = [
            part["text"]
            for part in content
            if isinstance(part, dict) and isinstance(part.get("text"), str)
        ]
        if text_parts:
            return "".join(text_parts)
    return None
