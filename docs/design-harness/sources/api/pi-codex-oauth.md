# Pi's Codex OAuth — proof that a ChatGPT account works without an API key

Pi authenticates `openai-codex` with a ChatGPT Plus/Pro subscription via OAuth: device-flow login against `auth.openai.com` / `api.openai.com/auth` (`codex_cli_simplified_flow`), storing `access` + `refresh` tokens and `accountId` in `~/.pi/agent/auth.json` with auto-refresh, then calling `https://chatgpt.com/backend-api`. Verified in the local install: `@earendil-works/pi-ai/dist/auth/oauth/openai-codex.js` and `@earendil-works/pi-coding-agent/docs/providers.md` (accessed 2026-09-05).

Grade: strong precedent — proves account-based auth works for a non-coding app's requests in principle; the same backend-api is the ChatGPT web app's own API. Translation traffic on the account is outside OpenAI's Codex-for-OSS endorsement, so throttling/ban risk is real but unquantified.
