---
id: chatgpt-account-no-api-key
type: idea
---

# Translation must work with the paid ChatGPT account, no OpenAI API key

The human has a paid ChatGPT account but no OpenAI API key, so translation should ride the existing ChatGPT account rather than metered API calls. Mechanism: the same subscription OAuth as [Pi's Codex login](../../sources/api/pi-codex-oauth.md) — device-flow login, stored refresh token, calls to chatgpt.com/backend-api. Qualifies [Translation uses the human's ChatGPT](translation-via-chatgpt.md). ToS-gray for non-coding traffic; keep a fallback engine option open.
