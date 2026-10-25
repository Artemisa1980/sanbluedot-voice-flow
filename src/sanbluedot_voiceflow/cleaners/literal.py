class LiteralCleaner:
    name = "literal"

    def clean(self, text: str, language_hint: str | None = None) -> str:
        del language_hint
        # whisper.cpp opens every segment with a space. The raw transcript keeps it (R2);
        # the delivered text must not land at the cursor with it.
        return text.strip()

