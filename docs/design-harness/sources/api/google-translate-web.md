# Google Translate keyless web endpoint

The translator uses `translate.googleapis.com/translate_a/single` as a last-resort machine-translation fallback when the contextual free-model providers are unavailable. It requires no API key and returns segmented translated text.

This is a web endpoint rather than the official Cloud Translation API, so availability and rate limits can change. It is only called after the contextual providers fail; names and handles are masked before the request.
