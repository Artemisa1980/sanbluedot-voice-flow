"""The one conservative cleanup instruction every provider receives.

Two providers cannot be compared on the same corpus if they are told different things,
and a safety instruction that drifts between adapters is a safety instruction nobody
owns. Local and cloud cleanup therefore share this text verbatim.
"""

CONSERVATIVE_SYSTEM_PROMPT = """Edit a voice transcript conservatively and return JSON only.
Remove fillers such as "um" and abandoned repetitions. When the speaker says
"X, no, actually Y", keep Y and remove X plus the correction cues. Add punctuation
and format paragraphs only when the structure is clear.
Preserve every remaining word in its original language; mixed language must stay mixed.
Never translate, paraphrase, add facts, change names, alter numbers, alter URLs, or
reinterpret code. When uncertain, preserve the original wording.
Example input: Please book Friday, no, actually Saturday.
Example output: {"cleaned_text":"Please book Saturday."}
Example input: Hola, um, I need el reporte.
Example output: {"cleaned_text":"Hola, I need el reporte."}"""

TRANSLATE_EN_SYSTEM_PROMPT = """Translate a spoken voice transcript into clear, idiomatic, professional English and return JSON only.
Remove verbal fillers such as "eh", "um", "este" and self-corrections.
Translate Spanish or mixed Spanish/English speech into natural US English suitable for professional communications.
Preserve proper names, technical terms, product names, URLs, file paths, numbers, and currencies.
Never invent facts or omit important points.
Example input: Hola, acabo de revisar el presupuesto y creo que debemos aprobarlo antes del mediodía.
Example output: {"cleaned_text":"Hello, I just reviewed the budget and I think we should approve it before noon."}
Example input: Por favor envíame los archivos del proyecto sanblue a mi correo.
Example output: {"cleaned_text":"Please send me the sanblue project files to my email."}"""

MEETING_NOTES_SYSTEM_PROMPT = """Format a spoken voice dictation into clear, structured Markdown meeting notes and action items, and return JSON only.
Remove conversational fillers such as "eh", "um", "este" and self-corrections.
Organize the content into:
- Key points / summary bullets.
- An "Action Items" checklist with Markdown checkboxes (`- [ ] ...`).
Keep the speaker's language (Spanish in Spanish, English in English).
Preserve all names, deadlines, numbers, and technical terms.
Example input: En la reunión acordamos que Juan revisa el código hoy, María envía la cotización mañana a las diez, y yo preparo la presentación para el viernes.
Example output: {"cleaned_text":"### Puntos Clave\n- Acuerdos de entrega y asignación de responsabilidades.\n\n### Action Items\n- [ ] Juan: Revisar el código hoy.\n- [ ] María: Enviar la cotización mañana a las 10:00.\n- [ ] Preparar la presentación para el viernes."}"""

CLEANED_TEXT_SCHEMA = {
    "type": "object",
    "properties": {"cleaned_text": {"type": "string"}},
    "required": ["cleaned_text"],
}


def output_token_budget(text: str) -> int:
    """Bound the reply to roughly the transcript's own length plus thinking budget.

    Modern reasoning models generate internal thought tokens alongside the structured
    output JSON. A 2048 token floor ensures the full cleaned/translated response fits
    without getting truncated by maxOutputTokens.
    """
    return max(2048, len(text.split()) * 8 + 512)
