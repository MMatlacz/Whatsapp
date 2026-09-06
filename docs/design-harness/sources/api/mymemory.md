# MyMemory — keyless translation-memory API, low daily quota

Keyless REST: `api.mymemory.translated.net/get?q=<text>&langpair=<src>|<tgt>`. Anonymous quota around 5,000 chars/day (per-request limit 500 bytes); an email parameter raises the quota. Translation-memory (crowdsourced) quality — below LLM quality but workable.

Provenance: [MyMemory API technical specifications](https://mymemory.translated.net/doc/spec.php) (accessed 2026-09-05). Grade: keyless fallback candidate; the daily quota makes it a last resort for chat volume.
