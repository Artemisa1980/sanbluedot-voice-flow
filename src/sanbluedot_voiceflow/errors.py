class VoiceFlowError(RuntimeError):
    """Base error for expected engine failures."""


class DependencyUnavailable(VoiceFlowError):
    """A required local binary, model, or service is unavailable."""


class TranscriptionError(VoiceFlowError):
    """The speech backend could not produce a transcript."""


class CleanupError(VoiceFlowError):
    """The cleanup backend could not produce safe output."""


class CleanupFailed(CleanupError):
    """Cleanup failed after transcription; the raw transcript is retained."""

    def __init__(
        self,
        message: str,
        raw_text: str,
        fallback_text: str | None = None,
        language: str | None = None,
        transcribe_seconds: float | None = None,
        cleanup_seconds: float | None = None,
        reason: str = "provider",
        rejected_text: str | None = None,
        personalized_text: str | None = None,
    ) -> None:
        super().__init__(message)
        # Corrections applied, snippets not expanded. The fallback text carries the
        # expansion, and reporting it as the CORRECTED layer showed an expansion as a
        # correction (D-41).
        self.personalized_text = personalized_text
        # Which side refused: "guard" when the conservative output guard rejected a
        # cleanup the provider did return, "provider" when the provider itself failed.
        # The two look identical to the speaker otherwise, and they call for opposite
        # responses: one says shorten the sentence, the other says wait or go local.
        self.reason = reason
        # What the provider actually returned when the guard refused it. Discarding it
        # unseen left the speaker with no way to judge a rejection they never saw, and
        # no way to take a cleanup that was in fact fine.
        self.rejected_text = rejected_text
        self.raw_text = raw_text
        self.fallback_text = raw_text if fallback_text is None else fallback_text
        self.language = language
        # A failed cleanup still spent measurable time. Carrying both stage durations
        # here keeps the failure path as honest as the success path.
        self.transcribe_seconds = transcribe_seconds
        self.cleanup_seconds = cleanup_seconds


class OutputError(VoiceFlowError):
    """The engine could not deliver text to the requested output."""
