import time
from collections.abc import Callable, Sequence
from pathlib import Path

from .cleaners.fillers import remove_fillers
from .contracts import Cleaner, PipelineResult, Transcriber
from .errors import CleanupFailed
from .memory import Correction, apply_corrections
from .output_guard import guard_conservative_cleanup, guard_fix_cleanup
from .snippets import Snippet, expand_snippets
from .take_back import has_take_back


class DictationPipeline:
    def __init__(
        self,
        transcriber: Transcriber,
        cleaner: Cleaner,
        corrections: Sequence[Correction] = (),
        snippets: Sequence[Snippet] = (),
        app_name: str | None = None,
        monotonic: Callable[[], float] = time.monotonic,
        model_only_for_take_back: bool = False,
    ) -> None:
        self._transcriber = transcriber
        self._cleaner = cleaner
        self._corrections = corrections
        self._snippets = snippets
        self._app_name = app_name
        # Injected so a test can assert the reported duration is the measured one and
        # not a constant. A displayed latency nobody can reproduce is not evidence.
        self._monotonic = monotonic
        # Set when the speech engine already punctuates (Parakeet). A `clean` dictation
        # then asks no model: the guard's fillers are deleted by rule. A spoken take-back
        # still goes to the model, because deciding what was withdrawn takes one.
        self._model_only_for_take_back = model_only_for_take_back

    def process(self, audio_path: Path) -> PipelineResult:
        started = self._monotonic()
        transcript = self._transcriber.transcribe(audio_path)
        transcribe_seconds = self._monotonic() - started
        return self.process_text(
            transcript.text,
            language=transcript.language,
            transcribe_seconds=transcribe_seconds,
        )

    def _clean_once(
        self,
        *,
        mode: str,
        raw_text: str,
        personalized_text: str,
        fallback: str,
        language: str | None,
        transcribe_seconds: float | None,
        cleanup_started: float,
    ) -> tuple[str, float, str]:
        """One cleanup in `mode`, through the guard that mode faces, snippets expanded."""
        try:
            if mode == "fix":
                cleaned = self._cleaner.clean(
                    personalized_text, language_hint=language, mode="fix"
                )
            elif mode == "translate":
                # Triggers are spoken in Spanish, so they expand before the translation:
                # translated first, "mi firma" became "my signature" and matched nothing
                # (D-58). The expansion itself then passes through the translation.
                cleaned = self._cleaner.clean(
                    expand_snippets(personalized_text, self._snippets, app_name=self._app_name),
                    language_hint=language,
                )
            else:
                cleaned = self._cleaner.clean(personalized_text, language_hint=language)
            cleanup_seconds = self._monotonic() - cleanup_started
            if mode in ("clean", "fix"):
                # The guard gets its own handler so a rejection is reported as a
                # rejection. Wrapped in the general one below it was indistinguishable
                # from the provider being unreachable, and the speaker could not tell
                # that the sentence, not the network, was what needed to change.
                # A fix may delete what the speaker took back, so it faces the guard
                # that allows deletion and still refuses every word they did not say.
                guard = guard_fix_cleanup if mode == "fix" else guard_conservative_cleanup
                label = "fix" if mode == "fix" else "conservative"
                try:
                    cleaned = guard(personalized_text, cleaned)
                except CleanupFailed:
                    raise
                except Exception as exc:
                    raise CleanupFailed(
                        f"The {label} guard refused the cleanup: {exc}",
                        raw_text=raw_text,
                        fallback_text=fallback,
                        personalized_text=personalized_text,
                        language=language,
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
                    personalized_text=personalized_text,
                    language=language,
                    transcribe_seconds=transcribe_seconds,
                    cleanup_seconds=cleanup_seconds,
                )
            # In translate mode, snippets already expanded on personalized_text before
            # translation (line 70). Expanding again here would violate R5b non-cascading.
            final_text = (
                cleaned
                if mode == "translate"
                else expand_snippets(cleaned, self._snippets, app_name=self._app_name)
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
                personalized_text=personalized_text,
                language=language,
                transcribe_seconds=transcribe_seconds,
                cleanup_seconds=self._monotonic() - cleanup_started,
            ) from exc
        return final_text, cleanup_seconds, cleaned

    def _without_model(
        self,
        *,
        personalized_text: str,
        cleanup_started: float,
        **_: object,
    ) -> tuple[str, float, str]:
        """The `clean` a punctuating engine needs: fillers out by rule, snippets expanded."""
        cleaned = remove_fillers(personalized_text)
        final_text = expand_snippets(cleaned, self._snippets, app_name=self._app_name)
        return final_text, self._monotonic() - cleanup_started, cleaned

    def process_text(
        self,
        raw_text: str,
        language: str | None = None,
        transcribe_seconds: float | None = None,
    ) -> PipelineResult:
        """Everything after transcription, for text that was never spoken here.

        A shortcut hands over text that was written rather than dictated, so there is no
        recording and no transcription stage. Entering here rather than calling a cleaner
        directly keeps the conservative output guard and the one stage order this class
        defines. Corrections and snippets apply only when the caller supplies them, and a
        shortcut supplies none (framework.md R3d).

        `transcribe_seconds` stays None on that path. R9 forbids a placeholder: no
        recognition happened, so the interface must show nothing rather than a zero.
        """
        # Confirmed corrections are deterministic personal memory, not model cleanup.
        # Keep both layers so the engine transcript remains independently recoverable.
        personalized_text = apply_corrections(raw_text, self._corrections)

        # Stripped because it is delivered text: the engine's leading segment space stays
        # in `raw_text` and `personalized_text`, never at the speaker's cursor.
        fallback = expand_snippets(
            personalized_text.strip(), self._snippets, app_name=self._app_name
        )

        cleanup_started = self._monotonic()
        mode = getattr(self._cleaner, "mode", "clean")
        # A spoken take-back — "borra eso", "no, mejor", "scratch that" — can only be
        # resolved by deleting words, which the conservative guard refuses. A `clean`
        # dictation that carries one runs as a fix first, on every engine that has a
        # model: the model decides what was withdrawn, and the fix guard still refuses
        # every word the speaker did not say. `literal` has no model and no mode.
        switch_to_fix = (
            mode == "clean"
            and hasattr(self._cleaner, "mode")
            and has_take_back(personalized_text)
        )
        attempt = dict(
            raw_text=raw_text,
            personalized_text=personalized_text,
            fallback=fallback,
            language=language,
            transcribe_seconds=transcribe_seconds,
            cleanup_started=cleanup_started,
        )
        no_model = (
            mode == "clean"
            and self._model_only_for_take_back
            and hasattr(self._cleaner, "mode")
        )
        cleaner_name = self._cleaner.name
        if switch_to_fix:
            try:
                final_text, cleanup_seconds, cleaner_output = self._clean_once(mode="fix", **attempt)
            except CleanupFailed as exc:
                # With a punctuating engine the filler rule needs no model, so a provider
                # failure on a take-back still gets it instead of the raw text (D-93).
                if exc.reason != "guard" and not no_model:
                    raise
                # The fix put in a word the speaker did not say. The dictation still gets
                # the ordinary cleanup rather than dropping straight to the transcript.
                if no_model:
                    final_text, cleanup_seconds, cleaner_output = self._without_model(**attempt)
                    cleaner_name = "fillers"
                else:
                    final_text, cleanup_seconds, cleaner_output = self._clean_once(mode=mode, **attempt)
        elif no_model:
            final_text, cleanup_seconds, cleaner_output = self._without_model(**attempt)
            # Named for what ran, so nothing reports a model that was never asked.
            cleaner_name = "fillers"
        else:
            final_text, cleanup_seconds, cleaner_output = self._clean_once(mode=mode, **attempt)

        if personalized_text and not final_text.strip():
            raise CleanupFailed(
                f"Cleanup with {self._cleaner.name!r} returned empty text.",
                raw_text=raw_text,
                fallback_text=fallback,
                personalized_text=personalized_text,
                language=language,
                transcribe_seconds=transcribe_seconds,
                cleanup_seconds=cleanup_seconds,
            )

        return PipelineResult(
            raw_text=raw_text,
            personalized_text=personalized_text,
            final_text=final_text,
            language=language,
            cleaner=cleaner_name,
            transcribe_seconds=transcribe_seconds,
            cleanup_seconds=cleanup_seconds,
            cleaner_output=cleaner_output,
        )
