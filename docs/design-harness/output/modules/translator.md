# Translator

Responsibility: incoming translation, contextual and account-based.

- Translates one incoming group message to Polish when the human clicks Translate
- Uses preceding conversation plus related quoted-message text as context; old history is loaded before the visible window
- Runs a free-model chain with automatic fallback: [OpenCode Zen](../../sources/api/opencode-zen-free.md) (Big Pickle / Muse Spark) → [OpenRouter :free](../../sources/api/openrouter-free.md) → [Google Translate keyless web endpoint](../../sources/api/google-translate-web.md) → keyless engines ([MyMemory](../../sources/api/mymemory.md) / [LibreTranslate](../../sources/api/libretranslate.md)); the Google fallback is used only after contextual providers fail
- Masks names and handles with placeholders before any provider call and restores them in the output — real names never leave the machine
- Retranslates with an added comment; the comment steers the new translation
- Keeps words from the global known-word list untranslated inside translated messages
- Never translates outgoing text — sending is as-typed

Provenance: [translate-incoming-to-polish](../../ideas/translate-incoming-to-polish.md), [translations-contextual](../../ideas/translations-contextual.md), [ban-safe-free-model-translation](../../ideas/ban-safe-free-model-translation.md), [free-engine-fallback](../../ideas/free-engine-fallback.md), [privacy-name-masking](../../ideas/privacy-name-masking.md), [retranslate-edit-translations](../../ideas/retranslate-edit-translations.md), [keep-known-words-untranslated](../../ideas/keep-known-words-untranslated.md) · evidence: [openai-multilingual](../../sources/api/openai-multilingual.md)
