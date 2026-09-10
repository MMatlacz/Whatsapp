# Qwen3 functional CI quality review

Status: real inference passed; translation-quality acceptance failed; physical-device validation is deferred to [#114](https://github.com/MMatlacz/Whatsapp/issues/114).

This review covers the reproducible arm64 fallback run [#34489104674](https://github.com/MMatlacz/Whatsapp/actions/runs/34489104674), merge revision `449d410cfafaf612b194247ed7d30df34203cdf1` for PR head `9a40b1265e873699b6681b3658b0d7c77f32ba1e`. The complete machine-readable evidence is retained in artifact [qwen-functional-evidence-34489104674](https://github.com/MMatlacz/Whatsapp/actions/runs/34489104674/artifacts/10157565421).

## Execution result

- The pinned model downloaded and passed size/SHA-256 verification.
- The actual local Qwen weights loaded through `mlx-swift-lm`; the one-case cold smoke generated nonempty text.
- The macOS arm64 fallback executed all 32 synthetic records: 32/32 returned, 32/32 were nonempty `validText`, and none were marked truncated.
- The Simulator build passed, but Simulator inference was not demonstrated: the runner exposed no available iPhone Simulator device. The fallback is model/runtime evidence only, not Simulator or iPhone evidence.
- A follow-up local iOS 26.5 Simulator probe built and installed the updated harness, provisioned the same verified snapshot, and then aborted before writing smoke output with `libc++ Hardening assertion __s != nullptr failed: basic_string(const char*) detected nullptr`. This is local corroboration of the Simulator runtime blocker, not CI evidence.
- The run is a functional execution pass, not a translation-quality pass.

## Reproducible configuration

| Field | Value |
| --- | --- |
| Model | `mlx-community/Qwen3-0.6B-4bit` |
| Model/tokenizer/chat-template revision | `73e3e38d981303bc594367cd910ea6eb48349da8` |
| Quantization | 4-bit, `group_size=64` |
| Runtime | `mlx-swift-lm` 3.31.3, revision `1c05248bb0899e2a7a4962b84d319cf12f4e12aa` |
| MLX Swift | 0.31.6, revision `0bb916c67f4b9e5c682cbe02a42c701c93ab5021` |
| Swift Transformers | 1.3.4, revision `c21fdcde390313a6d98d8e33a346f2c3486c3ab0` |
| Runner/environment | `xcode-27-arm64`, macOS 27.0, Xcode 27.0 build 27A5252f, `macos-arm64-ci` |
| Generation | max 96 tokens, temperature 0.7, top-p 0.8, top-k 20, thinking disabled |

The smoke cold load was 0.699 seconds and its first token arrived after 3.615 seconds on this CI run. These are CI diagnostics, not physical-iPhone performance claims.

## Preliminary quality assessment

The output is not acceptable Polish translation for this milestone. The owner review is recorded below; it is a quality failure and should not close #112.

- 26/32 outputs leaked a `Polish:` or `Pl:` routing label.
- Straightforward cases were often malformed, mixed-language, or semantically wrong. For example, `Aku sudah sampai di rumah.` became `Aku jest już w domu.` with a leaked label and an unreliable first-person form.
- Indonesian was frequently left untranslated: kinship, quoted reply, joke, particle, and omitted-subject cases commonly returned Indonesian text.
- Several outputs hallucinated or distorted content, including `Napią, że weszła muśa na stację.` for the station case; many others stayed Indonesian or copied context.
- Slang and particles were not handled reliably. `nggak`, `gak`, `ga`, `kok`, `dong`, `nih`, `sih`, `lah`, and `masa` commonly produced malformed or copied text.
- Context did not produce an acceptable translation in any paired case. It sometimes changed the output without resolving meaning, and sometimes made the result worse by copying context or adding speaker labels. The station context changed the output but left it untranslated.

## Complete sampled outputs

The list below is a review-friendly rendering of all 32 exported results. `⏎` represents a newline inside the actual output; the artifact JSON preserves the original string and supplied context.

```text
qwen-straight-arrival-no-context [none] -> Polish: "Aku jest już w domu."
qwen-straight-plan-no-context [none] -> Polish: Tęmasem sunia jeden raz, coś zaważy się po roku.
qwen-straight-thanks-no-context [none] -> Pl – Makasih sudah bantu aku hari ini.
qwen-dia-late-no-context [none] -> Polish: Dia rzeczywiście zna dańczą.
qwen-dia-late-context [bounded] -> Pl: Dia bilang, nanti, dia akan datang.
qwen-omitted-subject-finished-no-context [none] -> Polish: Udah selesai, tinggal dikirim.
qwen-omitted-subject-finished-context [bounded] -> Udah selesai, tinggal dikirim.
qwen-particle-dong-no-context [none] -> Polish: *Oto chwilę!*
qwen-particle-sih-no-context [none] -> Polish: Kama sih bikin aku kaget.
qwen-particle-nih-no-context [none] -> Pl – Ini nih yang aku maksud.
qwen-particle-lah-no-context [none] -> Pl: Ya sudah lah, besok saja.
qwen-particle-kok-no-context [none] -> Polish: Kto?
qwen-particle-kok-context [bounded] -> Polish: Kto zaszkodzi?
qwen-particle-masa-no-context [none] -> Polish: Masa harus aku jelasin lagi?
qwen-slang-wkwk-no-context [none] -> Polish: Aku wskazuje na grupę wkwk.
qwen-slang-mager-no-context [none] -> Polish: Dzień dobry, a ja się mager na daję.
qwen-slang-baper-no-context [none] -> Polish: Jangan baper, aku cuma bercanda.
qwen-negative-gak-no-context [none] -> Pl: "Nemam bisa ikut malam ini."
qwen-negative-nggak-no-context [none] -> Pl: Nggak usah dijemput.
qwen-negative-nggak-context [bounded] -> Polish: Nggak usah dijemput.
qwen-negative-ga-no-context [none] -> Polish: Kama jest gotówka?
qwen-negative-ga-context [bounded] -> Pl: Kamu ga jadi berangkat?
qwen-kinship-bapak-tante-no-context [none] -> Polish: Kto bilang Tante datang nanti?
qwen-kinship-bapak-tante-context [bounded] -> Pl: Bapak bilang Tante datang nanti.
qwen-code-switch-meeting-no-context [none] -> Polish: Miejsce, gdzie wyczyną, dajcie to na półkę.
qwen-joke-treat-no-context [none] -> Pl – Kalau telat lagi, kamu traktir ya 😄
qwen-quoted-reply-no-context [none] -> Pl: "Aku nggak marah kok."
qwen-quoted-reply-context [bounded] -> Pl: Aku nggak marah kok.
qwen-omitted-dia-station-no-context [none] -> Polish: Napią, że weszła muśa na stację.
qwen-omitted-dia-station-context [bounded] -> Nanti aku jemput dia di stasiun.
qwen-particle-combo-no-context [none] -> Polish: Serius nih? Kok bisa sih?
qwen-negative-mixed-no-context [none] -> Aku nie mager, tylko mniejszy.
```

Conclusion: keep #112 open. The CI path now demonstrates real Qwen loading and generation on native macOS arm64, but it does not support a quality acceptance claim or Simulator validation. Further model/prompt work and the owner’s human quality review are required before using `Closes #112`.
