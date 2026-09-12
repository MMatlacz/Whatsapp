# Physical Qwen evidence export

This directory preserves the raw synthetic export from the named-iPhone run
whose installed source revision was `7f24e65`. It is retained as the baseline
physical observation while the committed evidence-plumbing revision is rerun.

- `report.json` is the deterministic 32-fixture report.
- `summary.md` is the harness Markdown export.
- `results/` contains one JSON record per fixture.
- `cancellation.json` is the 0.1-second cancellation probe.

The export contains only source-controlled synthetic fixture content. It has no
real WhatsApp messages, cookies, pairing material, or account data. The report
records `offlineAfterProvisioning` as `notRun`; it must not be treated as an
offline acceptance result. The Activity Monitor trace is not committed; its
named measurement is recorded in the evaluation document.
