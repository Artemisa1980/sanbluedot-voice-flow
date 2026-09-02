class LiteralCleaner:
    name = "literal"

    def clean(self, text: str, language_hint: str | None = None) -> str:
        del language_hint
        return text

