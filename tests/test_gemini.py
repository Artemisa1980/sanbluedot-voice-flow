import json
import socket
import unittest
from urllib.error import HTTPError, URLError

from sanbluedot_voiceflow.cleaners.gemini import (
    CONTACT_AT_CAPACITY,
    CONTACT_DROPPED,
    CONTACT_TIMED_OUT,
    DEFAULT_MODEL,
    DEFAULT_TIMEOUT_SECONDS,
    MODEL_CHAIN,
    MINIMUM_RETRY_BUDGET_SECONDS,
    PER_MODEL_TIMEOUT_SECONDS,
    GeminiCleaner,
    describe_chain_failure,
    per_model_slice,
    model_chain,
)
from sanbluedot_voiceflow.errors import CleanupError
from unittest import mock

# The product lists one model (`MODEL_CHAIN`), but the walk still runs whenever an
# unlisted `--gemini-model` leads it. These tests pin a three-model chain so the walk
# itself stays covered whatever the product list holds.
THREE_MODEL_CHAIN = (DEFAULT_MODEL, "gemini-test-b", "gemini-test-c")


class ThreeModelChain(unittest.TestCase):
    def setUp(self) -> None:
        patcher = mock.patch(
            "sanbluedot_voiceflow.cleaners.gemini.MODEL_CHAIN", THREE_MODEL_CHAIN
        )
        patcher.start()
        self.addCleanup(patcher.stop)


SECRET = "not-a-real-key-fixture"


class FakeResponse:
    def __init__(self, body: str) -> None:
        self.body = body

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def read(self) -> bytes:
        return self.body.encode("utf-8")


def reply(cleaned: str) -> str:
    return json.dumps({
        "candidates": [
            {
                "content": {
                    "parts": [{"text": json.dumps({"cleaned_text": cleaned})}],
                    "role": "model",
                },
                "finishReason": "STOP",
            }
        ]
    })


class Recorder:
    def __init__(self, body: str | None = None, error: Exception | None = None) -> None:
        self.body = body
        self.error = error
        self.requests: list[object] = []
        self.timeouts: list[float | None] = []

    def __call__(self, request: object, timeout: float | None = None) -> FakeResponse:
        self.requests.append(request)
        self.timeouts.append(timeout)
        if self.error is not None:
            raise self.error
        return FakeResponse(self.body or "")


class SequenceRecorder(Recorder):
    """Serve one scripted outcome per call so a retry can be observed."""

    def __init__(self, outcomes: list[str | Exception]) -> None:
        super().__init__()
        self.outcomes = list(outcomes)

    def __call__(self, request: object, timeout: float | None = None) -> FakeResponse:
        self.requests.append(request)
        self.timeouts.append(timeout)
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return FakeResponse(outcome)


class Clock:
    """A clock the test advances, so no test waits on real time."""

    def __init__(self, step: float = 0.0) -> None:
        self.now = 0.0
        self.step = step
        self.slept: list[float] = []

    def monotonic(self) -> float:
        now = self.now
        self.now += self.step
        return now

    def sleep(self, seconds: float) -> None:
        self.slept.append(seconds)
        self.now += seconds


def unavailable(status: int = 503) -> HTTPError:
    return HTTPError("https://example.invalid", status, "Service Unavailable", {}, None)


def build(
    opener: Recorder,
    *,
    key: str | None = SECRET,
    mode: str = "clean",
    announced: list[str] | None = None,
    clock: Clock | None = None,
    fallback: bool = False,
    model: str = DEFAULT_MODEL,
) -> GeminiCleaner:
    clock = clock or Clock()
    return GeminiCleaner(
        model=model,
        opener=opener,
        mode=mode,
        announce=(announced.append if announced is not None else lambda _message: None),
        api_key_reader=lambda _provider: key,
        sleep=clock.sleep,
        monotonic=clock.monotonic,
        fallback=fallback,
    )


class TransmissionGuardTests(unittest.TestCase):
    def test_no_key_means_no_request_at_all(self) -> None:
        opener = Recorder(reply("Hola."))

        with self.assertRaises(CleanupError) as raised:
            build(opener, key=None).clean("hola")

        self.assertEqual(opener.requests, [])
        self.assertIn("set-key", str(raised.exception))

    def test_empty_text_never_reaches_the_provider(self) -> None:
        opener = Recorder(reply("x"))

        self.assertEqual(build(opener).clean(""), "")
        self.assertEqual(opener.requests, [])

    def test_the_provider_is_announced_before_anything_is_sent(self) -> None:
        announced: list[str] = []
        opener = Recorder(reply("Hola, mundo."))

        build(opener, announced=announced).clean("hola mundo")

        self.assertEqual(len(announced), 1)
        self.assertIn("gemini", announced[0])
        self.assertIn(DEFAULT_MODEL, announced[0])
        self.assertIn("No audio is sent", announced[0])

    def test_the_key_travels_in_the_header_and_not_in_the_url_or_body(self) -> None:
        opener = Recorder(reply("Hola."))

        build(opener).clean("hola")

        request = opener.requests[0]
        self.assertEqual(request.get_header("X-goog-api-key"), SECRET)
        self.assertNotIn(SECRET, request.full_url)
        self.assertNotIn(SECRET, request.data.decode("utf-8"))

    def test_only_transcript_text_is_sent(self) -> None:
        opener = Recorder(reply("Hola."))

        build(opener).clean("hola mundo", language_hint="es")

        request = opener.requests[0]
        self.assertIn(f"models/{DEFAULT_MODEL}:generateContent", request.full_url)
        payload = json.loads(request.data.decode("utf-8"))
        self.assertEqual(
            sorted(payload),
            [
                "contents",
                "generationConfig",
                "systemInstruction",
            ],
        )
        content_text = payload["contents"][0]["parts"][0]["text"]
        self.assertIn("hola mundo", content_text)
        self.assertIn("es", content_text)
        self.assertEqual(payload["generationConfig"]["responseMimeType"], "application/json")
        self.assertIn("cleaned_text", payload["generationConfig"]["responseSchema"]["properties"])
        self.assertIn("Edit a voice transcript", payload["systemInstruction"]["parts"][0]["text"])
        self.assertEqual(opener.timeouts, [DEFAULT_TIMEOUT_SECONDS])

    def test_translate_mode_uses_translation_system_prompt_and_announcement(self) -> None:
        announced: list[str] = []
        opener = Recorder(reply("Hello world."))

        result = build(opener, mode="translate", announced=announced).clean(
            "hola mundo", language_hint="es"
        )

        self.assertEqual(result, "Hello world.")
        self.assertEqual(len(announced), 1)
        self.assertIn("translate", announced[0])
        request = opener.requests[0]
        payload = json.loads(request.data.decode("utf-8"))
        self.assertIn("Translate a spoken voice transcript", payload["systemInstruction"]["parts"][0]["text"])

    def test_meeting_mode_uses_meeting_system_prompt_and_announcement(self) -> None:
        announced: list[str] = []
        opener = Recorder(reply("### Action Items\n- [ ] Task 1"))

        result = build(opener, mode="meeting", announced=announced).clean(
            "Juan revisa el código", language_hint="es"
        )

        self.assertEqual(result, "### Action Items\n- [ ] Task 1")
        self.assertEqual(len(announced), 1)
        self.assertIn("meeting", announced[0])
        request = opener.requests[0]
        payload = json.loads(request.data.decode("utf-8"))
        self.assertIn("Format a spoken voice dictation into clear, structured Markdown meeting notes", payload["systemInstruction"]["parts"][0]["text"])

class ResponseTests(unittest.TestCase):
    def test_the_cleaned_text_is_returned(self) -> None:
        self.assertEqual(
            build(Recorder(reply("Hola, mundo."))).clean("hola mundo"),
            "Hola, mundo.",
        )

    def test_a_response_with_candidates_array_extracts_text(self) -> None:
        body = json.dumps({
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {"text": '{"cleaned_text": "Buenos días."}'}
                        ]
                    }
                }
            ]
        })
        self.assertEqual(build(Recorder(body)).clean("buenos dias"), "Buenos días.")

    def test_a_response_wrapped_in_markdown_code_fences_is_parsed(self) -> None:
        body = json.dumps({
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {"text": '```json\n{"cleaned_text": "Buenos días."}\n```'}
                        ]
                    }
                }
            ]
        })
        self.assertEqual(build(Recorder(body)).clean("buenos dias"), "Buenos días.")

    def test_a_response_without_output_text_falls_back_to_the_last_step(self) -> None:
        body = json.dumps(
            {
                "steps": [
                    {"type": "thought", "content": [{"type": "text", "text": "ignored"}]},
                    {
                        "type": "model_output",
                        "content": [
                            {"type": "text", "text": json.dumps({"cleaned_text": "Hola."})}
                        ],
                    },
                ]
            }
        )

        self.assertEqual(build(Recorder(body)).clean("hola"), "Hola.")

    def test_split_text_parts_are_reassembled_before_parsing(self) -> None:
        body = json.dumps(
            {
                "steps": [
                    {
                        "type": "model_output",
                        "content": [
                            {"type": "text", "text": '{"cleaned_'},
                            {"type": "text", "text": 'text":"Hola."}'},
                        ],
                    }
                ]
            }
        )

        self.assertEqual(build(Recorder(body)).clean("hola"), "Hola.")

    def test_invalid_json_is_reported_as_a_cleanup_error(self) -> None:
        with self.assertRaises(CleanupError):
            build(Recorder("not json at all")).clean("hola")

    def test_a_reply_without_cleaned_text_is_refused(self) -> None:
        body = json.dumps({"output_text": json.dumps({"text": "Hola."})})

        with self.assertRaises(CleanupError):
            build(Recorder(body)).clean("hola")

    def test_empty_cleaned_text_is_refused(self) -> None:
        with self.assertRaises(CleanupError):
            build(Recorder(reply("   "))).clean("hola")


class FailureTests(ThreeModelChain):
    def test_an_http_error_reports_the_status_without_the_key(self) -> None:
        error = HTTPError("https://example.invalid", 429, "Too Many Requests", {}, None)

        with self.assertRaises(CleanupError) as raised:
            build(Recorder(error=error)).clean("hola")

        self.assertIn("429", str(raised.exception))
        self.assertNotIn(SECRET, str(raised.exception))

    def test_an_unreachable_provider_becomes_a_cleanup_error(self) -> None:
        with self.assertRaises(CleanupError):
            build(Recorder(error=URLError("offline"))).clean("hola")

    def test_an_unreachable_network_is_not_reported_as_a_slow_provider(self) -> None:
        """Nothing left the Mac, so nothing can be said about Google's speed.

        A name that does not resolve raised the same internal timeout as a slow reply,
        so an offline machine was told every model "ran out of the time budget" —
        instantly, having waited for none of them. R6 asks what happened to each model
        this run contacted, and this run contacted nothing.
        """
        opener = Recorder(error=URLError(socket.gaierror(8, "nodename nor servname provided")))

        with self.assertRaises(CleanupError) as raised:
            build(opener, fallback=True).clean("hola")

        message = str(raised.exception)
        self.assertIn("could not be reached", message)
        self.assertNotIn("time budget", message)
        self.assertNotIn("capacity", message)

    def test_an_unreachable_network_stops_the_chain_at_the_first_model(self) -> None:
        """Walking the rest costs the speaker time and proves nothing.

        The chain exists to survive one busy model. When the machine has no route to the
        provider, every model behind it is just as unreachable.
        """
        opener = Recorder(error=URLError(socket.gaierror(8, "nodename nor servname provided")))

        with self.assertRaises(CleanupError):
            build(opener, fallback=True).clean("hola")

        self.assertEqual(len(opener.requests), 1)

    def test_a_dropped_connection_still_walks_the_chain(self) -> None:
        """A reset mid-call ends the attempt, not the route to the provider.

        Telling a timeout apart from an unreachable host first sent every non-timeout
        socket error straight to a failure, which cost the chain a recovery it used to
        make: the connection was there, one attempt died on it.
        """
        opener = SequenceRecorder([ConnectionResetError("reset by peer"), reply("Hola.")])

        self.assertEqual(build(opener, fallback=True).clean("hola"), "Hola.")
        self.assertEqual(len(opener.requests), 2)

    def test_a_dropped_connection_is_not_called_a_time_budget(self) -> None:
        """The message says what happened. A reset is not the clock running out."""
        opener = Recorder(error=ConnectionResetError("reset by peer"))

        with self.assertRaises(CleanupError) as raised:
            build(opener, fallback=True).clean("hola")

        message = str(raised.exception)
        self.assertIn("dropped the connection", message)
        self.assertNotIn("time budget", message)
        self.assertNotIn("capacity", message)

    def test_a_real_timeout_still_walks_the_chain(self) -> None:
        """The separation must not cost the fallback its reason to exist."""
        opener = SequenceRecorder([TimeoutError("slow"), reply("Hola.")])

        self.assertEqual(build(opener, fallback=True).clean("hola"), "Hola.")
        self.assertEqual(len(opener.requests), 2)

    def test_a_timeout_becomes_a_cleanup_error(self) -> None:
        with self.assertRaises(CleanupError):
            build(Recorder(error=TimeoutError("slow"))).clean("hola")


class TransientCapacityTests(unittest.TestCase):
    """A 503 is Google reporting capacity, not a rejected request.

    Measured live on 2026-08-31: 6 of 9 calls to `gemini-3.7-flash` and 2 of 6 to
    `gemini-3.6-flash` returned 503, while every successful reply took longer than the
    former 20-second ceiling.
    """

    def test_the_default_budget_outlasts_the_slowest_measured_reply(self) -> None:
        self.assertGreater(DEFAULT_TIMEOUT_SECONDS, 34.55)

    def test_a_503_is_retried_once_and_the_second_reply_is_delivered(self) -> None:
        opener = SequenceRecorder([unavailable(), reply("Hola.")])
        announced: list[str] = []

        result = build(opener, announced=announced).clean("hola")

        self.assertEqual(result, "Hola.")
        self.assertEqual(len(opener.requests), 2)
        self.assertTrue(any("Retrying once" in message for message in announced))

    def test_a_second_503_is_not_retried_again(self) -> None:
        opener = SequenceRecorder([unavailable(), unavailable()])

        with self.assertRaises(CleanupError) as raised:
            build(opener).clean("hola")

        self.assertEqual(len(opener.requests), 2)
        self.assertIn("capacity", str(raised.exception))

    def test_a_rejected_request_is_never_sent_twice(self) -> None:
        for status in (400, 401, 403, 429):
            with self.subTest(status=status):
                opener = SequenceRecorder([unavailable(status), reply("Hola.")])

                with self.assertRaises(CleanupError):
                    build(opener).clean("hola")

                self.assertEqual(len(opener.requests), 1)

    def test_the_retry_shares_one_budget_instead_of_doubling_the_wait(self) -> None:
        clock = Clock()
        opener = SequenceRecorder([unavailable(), reply("Hola.")])

        build(opener, clock=clock).clean("hola")

        first, second = opener.timeouts
        self.assertEqual(first, DEFAULT_TIMEOUT_SECONDS)
        self.assertEqual(second, DEFAULT_TIMEOUT_SECONDS - clock.slept[0])
        self.assertLessEqual(first + second, 2 * DEFAULT_TIMEOUT_SECONDS)

    def test_a_slow_503_falls_back_rather_than_making_the_speaker_wait_twice(self) -> None:
        # Each clock read advances 22 seconds, so the failure consumed most of the
        # budget and no retry can finish inside it.
        clock = Clock(step=22.0)
        opener = SequenceRecorder([unavailable(), reply("Hola.")])

        with self.assertRaises(CleanupError):
            build(opener, clock=clock).clean("hola")

        self.assertEqual(len(opener.requests), 1)


class ModelChainTests(ThreeModelChain):
    """A 503 is one model being busy, so the next measured model gets the text.

    Falling back exists to save the cleanup, never to make the speaker wait longer than
    the single timeout budget the whole call already has.
    """

    def test_the_chain_puts_the_preferred_model_first(self) -> None:
        self.assertEqual(model_chain(THREE_MODEL_CHAIN[1])[0], THREE_MODEL_CHAIN[1])
        self.assertEqual(
            set(model_chain(THREE_MODEL_CHAIN[1])), set(THREE_MODEL_CHAIN)
        )

    def test_an_unknown_preferred_model_still_leads_its_own_chain(self) -> None:
        chain = model_chain("gemini-9-flash")
        self.assertEqual(chain[0], "gemini-9-flash")
        self.assertEqual(chain[1:], THREE_MODEL_CHAIN)

    def test_a_busy_model_hands_the_text_to_the_next_one(self) -> None:
        opener = SequenceRecorder([unavailable(), unavailable(), reply("Hola.")])
        announced: list[str] = []

        cleaner = build(opener, announced=announced, fallback=True)
        self.assertEqual(cleaner.clean("hola"), "Hola.")

        # Two requests for the preferred model (first try plus its retry), then the second.
        self.assertEqual(len(opener.requests), 3)
        self.assertIn(THREE_MODEL_CHAIN[1], opener.requests[2].full_url)

    def test_the_model_that_answered_is_reported(self) -> None:
        opener = SequenceRecorder([unavailable(), unavailable(), reply("Hola.")])
        cleaner = build(opener, fallback=True)

        cleaner.clean("hola")

        self.assertEqual(cleaner.answered_with, THREE_MODEL_CHAIN[1])

    def test_no_fallback_means_the_answer_names_the_preferred_model(self) -> None:
        opener = SequenceRecorder([reply("Hola.")])
        cleaner = build(opener, fallback=True)

        cleaner.clean("hola")

        self.assertEqual(cleaner.answered_with, DEFAULT_MODEL)

    def test_a_rejected_request_stops_the_chain_instead_of_walking_it(self) -> None:
        opener = SequenceRecorder([unavailable(400), reply("Hola.")])

        with self.assertRaises(CleanupError):
            build(opener, fallback=True).clean("hola")

        self.assertEqual(len(opener.requests), 1)

    def test_the_whole_chain_is_announced_before_anything_is_sent(self) -> None:
        announced: list[str] = []

        build(SequenceRecorder([reply("Hola.")]), announced=announced,
              fallback=True).clean("hola")

        for model in THREE_MODEL_CHAIN:
            self.assertIn(model, announced[0])
        self.assertIn("No audio is sent", announced[0])

    def test_an_exhausted_budget_stops_the_chain_early(self) -> None:
        # Each clock read advances 20 seconds, so after the first model there is not
        # enough budget left for another to be worth trying.
        clock = Clock(step=20.0)
        opener = SequenceRecorder([unavailable(), reply("Hola.")])

        with self.assertRaises(CleanupError):
            build(opener, clock=clock, fallback=True).clean("hola")

        self.assertEqual(len(opener.requests), 1)

    def test_every_model_busy_falls_back_to_the_local_transcript(self) -> None:
        opener = SequenceRecorder([unavailable()] * 6)

        with self.assertRaises(CleanupError) as raised:
            build(opener, fallback=True).clean("hola")

        self.assertIn("capacity", str(raised.exception))
        for model in THREE_MODEL_CHAIN:
            self.assertIn(model, str(raised.exception))

    def test_the_last_model_timing_out_still_names_what_was_contacted(self) -> None:
        # Found by the 2026-09-02 gate: this raise site bypassed the record of what the
        # run contacted, so the message named no model at all — neither the one that
        # timed out nor the ones that were busy before it.
        opener = SequenceRecorder([
            unavailable(), unavailable(),
            unavailable(), unavailable(),
            TimeoutError("slow"),
        ])

        with self.assertRaises(CleanupError) as raised:
            build(opener, fallback=True).clean("hola")

        message = str(raised.exception)
        self.assertIn(THREE_MODEL_CHAIN[0], message)
        self.assertIn(THREE_MODEL_CHAIN[2], message)
        self.assertIn("time budget", message)
        self.assertIn("capacity", message)

    def test_the_failure_never_calls_an_uncontacted_model_busy(self) -> None:
        # The budget runs out after the first model, so the other two are never sent
        # anything. Reporting them as at capacity is a claim about Google's
        # availability that nothing in this run measured.
        clock = Clock(step=20.0)
        opener = SequenceRecorder([unavailable(), reply("Hola."), reply("Hola.")])

        with self.assertRaises(CleanupError) as raised:
            build(opener, clock=clock, fallback=True).clean("hola")

        message = str(raised.exception)
        self.assertEqual(len(opener.requests), 1)
        self.assertIn("Not contacted", message)
        for skipped in THREE_MODEL_CHAIN[1:]:
            self.assertNotIn(f"{skipped} was at capacity", message)
            self.assertIn(skipped, message.split("Not contacted", 1)[1])


class PerModelBudgetTests(ThreeModelChain):
    """No single model may spend the whole budget and starve the rest of the chain.

    Measured live on 2026-08-31: a busy `gemini-3.7-flash` consumed all 45 seconds, so
    `gemini-3.5-flash`, which answered the same prompt in 5 seconds, was never reached.
    """

    def test_an_earlier_model_gets_only_its_slice(self) -> None:
        opener = SequenceRecorder([reply("Hola.")])

        build(opener, fallback=True).clean("hola")

        self.assertEqual(opener.timeouts, [PER_MODEL_TIMEOUT_SECONDS])

    def test_the_last_model_may_use_whatever_is_left(self) -> None:
        opener = SequenceRecorder([reply("Hola.")])

        build(opener, fallback=False).clean("hola")

        self.assertEqual(opener.timeouts, [DEFAULT_TIMEOUT_SECONDS])

    def test_a_slice_running_out_hands_over_instead_of_giving_up(self) -> None:
        # The first model's read times out inside its own slice, with budget to spare.
        opener = SequenceRecorder([TimeoutError("slow"), reply("Hola.")])
        announced: list[str] = []

        cleaner = build(opener, announced=announced, fallback=True)
        self.assertEqual(cleaner.clean("hola"), "Hola.")

        self.assertEqual(cleaner.answered_with, THREE_MODEL_CHAIN[1])
        self.assertTrue(any("ran out of its share" in m for m in announced))

    def test_the_slice_never_exceeds_the_whole_budget(self) -> None:
        self.assertLessEqual(
            PER_MODEL_TIMEOUT_SECONDS * len(THREE_MODEL_CHAIN), DEFAULT_TIMEOUT_SECONDS
        )

    def test_the_slice_adapts_to_a_longer_chain(self) -> None:
        # `--gemini-model` accepts any identifier, so an unlisted model makes the chain
        # longer than THREE_MODEL_CHAIN. A fixed slice would spend the budget before reaching
        # a healthy model.
        self.assertEqual(per_model_slice(45.0, 3), 15.0)
        self.assertEqual(per_model_slice(45.0, 4), 11.25)
        self.assertLessEqual(per_model_slice(45.0, 4) * 4, 45.0)

    def test_the_slice_never_falls_below_the_floor(self) -> None:
        self.assertEqual(per_model_slice(9.0, 9), MINIMUM_RETRY_BUDGET_SECONDS)

    def test_a_single_model_keeps_the_whole_budget(self) -> None:
        self.assertEqual(per_model_slice(45.0, 1), 45.0)

    def test_the_announcement_never_names_a_model_it_did_not_contact(self) -> None:
        # The budget runs out after the first model, so only that one may be named as
        # contacted and no promise may be made about the next.
        clock = Clock(step=20.0)
        opener = SequenceRecorder([unavailable(), reply("Hola.")])
        announced: list[str] = []

        with self.assertRaises(CleanupError):
            build(opener, announced=announced, clock=clock, fallback=True).clean("hola")

        self.assertEqual(len(opener.requests), 1)
        self.assertFalse(
            any("Trying" in m for m in announced),
            f"promised a model it never contacted: {announced}",
        )


class ChainFailureMessageTests(unittest.TestCase):
    """The message reports what happened, model by model, and nothing more."""

    def test_one_busy_model_is_named_alone(self) -> None:
        message = describe_chain_failure([("gemini-3.5-flash", CONTACT_AT_CAPACITY)])
        self.assertEqual(message, "Gemini is at capacity (gemini-3.5-flash).")

    def test_every_contacted_model_busy_says_so(self) -> None:
        message = describe_chain_failure(
            [(model, CONTACT_AT_CAPACITY) for model in THREE_MODEL_CHAIN]
        )
        self.assertIn("Every Gemini model contacted is at capacity", message)
        for model in THREE_MODEL_CHAIN:
            self.assertIn(model, message)

    def test_a_slow_model_is_not_called_busy(self) -> None:
        message = describe_chain_failure([("gemini-3.7-flash", CONTACT_TIMED_OUT)])
        self.assertIn("time budget", message)
        self.assertNotIn("capacity", message)

    def test_mixed_reasons_are_reported_per_model(self) -> None:
        message = describe_chain_failure([
            ("gemini-3.5-flash", CONTACT_AT_CAPACITY),
            ("gemini-3.6-flash", CONTACT_TIMED_OUT),
        ])
        self.assertIn("gemini-3.5-flash was at capacity", message)
        self.assertIn("gemini-3.6-flash ran out of the time budget", message)

    def test_skipped_models_are_named_as_skipped(self) -> None:
        message = describe_chain_failure(
            [("gemini-3.5-flash", CONTACT_AT_CAPACITY)],
            skipped=["gemini-3.6-flash", "gemini-3.7-flash"],
        )
        head, tail = message.split("Not contacted", 1)
        self.assertNotIn("gemini-3.6-flash", head)
        self.assertIn("gemini-3.6-flash", tail)
        self.assertIn("gemini-3.7-flash", tail)

    def test_a_dropped_model_is_named_as_dropped(self) -> None:
        message = describe_chain_failure([("gemini-3.5-flash", CONTACT_DROPPED)])
        self.assertIn("dropped the connection", message)
        self.assertNotIn("time budget", message)

    def test_three_reasons_are_reported_per_model(self) -> None:
        message = describe_chain_failure([
            ("gemini-3.5-flash", CONTACT_AT_CAPACITY),
            ("gemini-3.6-flash", CONTACT_TIMED_OUT),
            ("gemini-3.7-flash", CONTACT_DROPPED),
        ])
        self.assertIn("gemini-3.5-flash was at capacity", message)
        self.assertIn("gemini-3.6-flash ran out of the time budget", message)
        self.assertIn("gemini-3.7-flash dropped the connection", message)

    def test_contacting_nothing_says_nothing_was_contacted(self) -> None:
        message = describe_chain_failure([], skipped=list(THREE_MODEL_CHAIN))
        self.assertIn("No Gemini model was contacted", message)


if __name__ == "__main__":
    unittest.main()
