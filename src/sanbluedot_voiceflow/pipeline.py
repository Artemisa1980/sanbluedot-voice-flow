import time
from collections.abc import Callable, Sequence
from pathlib import Path

from .contracts import Cleaner, PipelineResult, Transcriber
from .errors import CleanupFailed
from .memory import Correction, apply_corrections
from .output_guard import guard_conservative_cleanup
from .snippets import Snippet, expand_snippets


class DictationPipeline:
    def __init__(
        self,
        transcriber: Transcriber,
        cleaner: Cleaner,
        corrections: Sequence[Correction] = (),
        snippets: Sequence[Snippet] = (),
        context_text: str | None = None,
        app_name: str | None = None,
        monotonic: Callable[[], float] = time.monotonic,
    ) -> None:
        self._transcriber = transcriber
        self._cleaner = cleaner
        self._corrections = corrections
        self._snippets = snippets
        self._context_text = context_text
        self._app_name = app_name
        # Injected so a test can assert the reported duration is the measured one and
        # not a constant. A displayed latency nobody can reproduce is not evidence.
        self._monotonic = monotonic

    def process(self, audio_path: Path) -> PipelineResult:
        started = self._monotonic()
        transcript = self._transcriber.transcribe(audio_path)
        transcribe_seconds = self._monotonic() - started
        raw_text = transcript.text
        # Confirmed corrections are deterministic personal memory, not model cleanup.
        # Keep both layers so the engine transcript remains independently recoverable.
        personalized_text = apply_corrections(raw_text, self._corrections)

        fallback = expand_snippets(
            personalized_text, self._snippets, app_name=self._app_name
        )

        cleanup_started = self._monotonic()
        cleanup_seconds: float | None = None
        mode = getattr(self._cleaner, "mode", "clean")
        text_to_clean = (
            f"Original text:\n{self._context_text}\n\nInstruction:\n{personalized_text}"
            if self._context_text and mode == "transform"
            else personalized_text
        )
        try:
            cleaned = self._cleaner.clean(
                text_to_clean,
                language_hint=transcript.language,
            )
            cleanup_seconds = self._monotonic() - cleanup_started
            if mode == "clean":
                # The guard gets its own handler so a rejection is reported as a
                # rejection. Wrapped in the general one below it was indistinguishable
                # from the provider being unreachable, and the speaker could not tell
                # that the sentence, not the network, was what needed to change.
                try:
                    cleaned = guard_conservative_cleanup(personalized_text, cleaned)
                except CleanupFailed:
                    raise
                except Exception as exc:
                    raise CleanupFailed(
                        f"The conservative guard refused the cleanup: {exc}",
                        raw_text=raw_text,
                        fallback_text=fallback,
                        language=transcript.language,
                        transcribe_seconds=transcribe_seconds,
                        cleanup_seconds=cleanup_seconds,
                        reason="guard",
                        rejected_text=cleaned,
                    ) from exc
            elif personalized_text and not cleaned.strip():
                raise CleanupFailed(
                    f"Cleanup with {self._cleaner.name!r} returned empty text.",
                    raw_text=raw_text,
                    fallback_text=fallback,
                    language=transcript.language,
                    transcribe_seconds=transcribe_seconds,
                    cleanup_seconds=cleanup_seconds,
                )
            final_text = expand_snippets(
                cleaned, self._snippets, app_name=self._app_name
            )
        except CleanupFailed:
            # Already carries its raw and fallback text. Re-wrapping it here doubled the
            # message the speaker sees.
            raise
        except Exception as exc:
            raise CleanupFailed(
                f"Cleanup with {self._cleaner.name!r} failed: {exc}",
                raw_text=raw_text,
                fallback_text=fallback,
                language=transcript.language,
                transcribe_seconds=transcribe_seconds,
                cleanup_seconds=self._monotonic() - cleanup_started,
            ) from exc

        if personalized_text and not final_text.strip():
            raise CleanupFailed(
                f"Cleanup with {self._cleaner.name!r} returned empty text.",
                raw_text=raw_text,
                fallback_text=fallback,
                language=transcript.language,
                transcribe_seconds=transcribe_seconds,
                cleanup_seconds=cleanup_seconds,
            )

        return PipelineResult(
            raw_text=raw_text,
            personalized_text=personalized_text,
            final_text=final_text,
            language=transcript.language,
            cleaner=self._cleaner.name,
            transcribe_seconds=transcribe_seconds,
            cleanup_seconds=cleanup_seconds,
        )
