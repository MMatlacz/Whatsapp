---
id: free-engine-fallback
type: idea
---

# Translation falls back to keyless engines if the free-model provider fails

If the ban-safe free-model provider (OpenRouter :free / OpenCode Zen) fails or rate-limits, translation falls back to a keyless Google Translate web endpoint, then to ([MyMemory](../sources/api/mymemory.md) / [LibreTranslate](../sources/api/libretranslate.md)) so the app keeps working. The Google fallback is only used after contextual providers fail; names and handles remain masked.
