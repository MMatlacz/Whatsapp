## Summary

<!-- Explain what changed and why. Keep this short and concrete. -->

-

## Issue

Closes #<issue-number>

<!--
Use exactly one closing reference.

The issue must be small enough that this PR satisfies all of its acceptance criteria.
If the issue is too broad, split it into smaller issues before implementing and link this PR to the smaller issue instead.

Use "Related to #<issue-number>" only for background context. A PR with only a related issue reference should not be merged as normal implementation work.
-->

## Validation

<!-- List the checks you actually ran. Do not claim physical-device validation unless it was performed. -->

- [ ] Secret checks pass
- [ ] Relevant build/test/lint checks pass
- [ ] Manual validation completed, if required by the issue

## Security and privacy

- [ ] No credentials, tokens, private keys, session state, `.env*`, `.pi/`, signing material, or generated sensitive logs are committed
- [ ] No unnecessary personal data, WhatsApp account data, message contents, or local machine paths are committed
- [ ] New logs/debug output avoid printing secrets and personal data

## Scope control

- [ ] This PR closes exactly one issue
- [ ] All acceptance criteria for that issue are met
- [ ] Any follow-up work is tracked in a separate issue
