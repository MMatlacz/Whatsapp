# Qwen3 functional CI quality review

Status: real inference passed; translation-quality acceptance failed; physical-device validation is deferred to [#114](https://github.com/MMatlacz/Whatsapp/issues/114).

This review covers the reproducible arm64 fallback run [#34484983755](https://github.com/MMatlacz/Whatsapp/actions/runs/34484983755), commit `0c9fa4fa4bccf030f3375a0d9fe17bc6b6643eb5`. The complete machine-readable evidence is retained in artifact [qwen-functional-evidence-34484983755](https://github.com/MMatlacz/Whatsapp/actions/runs/34484983755/artifacts/10156056960).

## Execution result

- The pinned model downloaded and passed size/SHA-256 verification.
- The actual local Qwen weights loaded through `mlx-swift-lm`; the one-case cold smoke generated nonempty text.
- The macOS arm64 fallback executed all 32 synthetic records: 32/32 returned, 32/32 were nonempty `validText`, and none were marked truncated.
- The Simulator build passed, but Simulator inference was not demonstrated: the runner exposed no available iPhone Simulator device. The fallback is model/runtime evidence only, not Simulator or iPhone evidence.
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

The smoke cold load was 1.239 seconds and its first token arrived after 4.009 seconds on this CI run. These are CI diagnostics, not physical-iPhone performance claims.

## Preliminary quality assessment

The output is not acceptable Polish translation for this milestone. A human owner review remains required; this preliminary review should not close #112.

- 26/32 outputs leaked a `Polish:` or `Pl:` routing label.
- Straightforward cases were often malformed, mixed-language, or semantically wrong. For example, `Aku sudah sampai di rumah.` became `Aku wychodzimy do domu.` rather than an arrival statement.
- Indonesian was frequently left untranslated: kinship, quoted reply, joke, particle, and omitted-subject cases commonly returned Indonesian text.
- Several outputs hallucinated or distorted content, including `Nadia jemput jejaka do stacji.` for the station case and a `P1`/`P2` context transcript for the `ga` case.
- Slang and particles were not handled reliably. `nggak` produced an emoji in the context-free case; `kok`, `dong`, `nih`, `sih`, `lah`, and `masa` produced malformed or copied text.
- Context did not produce an acceptable translation in any paired case. It sometimes changed the output without resolving meaning, and sometimes made the result worse by copying context or adding speaker labels. The station context changed the output but left it untranslated.

## Complete sampled outputs

The list below is a review-friendly rendering of all 32 exported results. `⏎` represents a newline inside the actual output; the artifact JSON preserves the original string and supplied context.

```text
qwen-straight-arrival-no-context [none] -> Polish: "Aku wychodzimy do domu."
qwen-straight-plan-no-context [none] -> Pl: Besow tym kiedy mamy jam na siadu.
qwen-straight-thanks-no-context [none] -> Polish: Młody mały dawek – znać się wtedy poza małymi.
qwen-dia-late-no-context [none] -> Polish: Dia bilang, że zjadli.
qwen-dia-late-context [bounded] -> Polish:  ⏎Dia przez chwila odpowiedział.
qwen-omitted-subject-finished-no-context [none] -> Polish: Udah selesai, tinggal dikirim.
qwen-omitted-subject-finished-context [bounded] -> Polish: Udah selesai, tinggal dikirim.
qwen-particle-dong-no-context [none] -> Polish: Warto daj mużdliwą odpowiedź.
qwen-particle-sih-no-context [none] -> Pl: Kamil sih bikin aku kaget.
qwen-particle-nih-no-context [none] -> Polish: "To to, coe mokas."
qwen-particle-lah-no-context [none] -> Pl: Ya sudah lah, besok saja.
qwen-particle-kok-no-context [none] -> Polish: Kto czyli? Wszędzcie?
qwen-particle-kok-context [bounded] -> Polish:  ⏎Ko mu przypominając, że chcesz wiedzieć, co powinien chodzić.
qwen-particle-masa-no-context [none] -> Pl: Masa harus aku jelasin lagi?
qwen-slang-wkwk-no-context [none] -> Polish: **Aku wchodzi w grupę wkwk.**
qwen-slang-mager-no-context [none] -> Polish: "To maer baer."
qwen-slang-baper-no-context [none] -> Polish: Niebie, to cuma bercanda.
qwen-negative-gak-no-context [none] -> Polish: Mój czas nie mogę wziąć udział w tym dniu.
qwen-negative-nggak-no-context [none] -> Polish: 🚤
qwen-negative-nggak-context [bounded] -> Pl – Nggak usah dijemput.
qwen-negative-ga-no-context [none] -> Polish: Kąma nie ma jadę?
qwen-negative-ga-context [bounded] -> P1: Kamu ga jadi berangkat?  ⏎P2: Iya, tapi hujan deras sekali.
qwen-kinship-bapak-tante-no-context [none] -> Bapak bilang Tante datang nanti.
qwen-kinship-bapak-tante-context [bounded] -> Bapak bilang Tante datang nanti.
qwen-code-switch-meeting-no-context [none] -> Polish: Jana zdraduje się, więc możemy sięgnąć dalej.
qwen-joke-treat-no-context [none] -> Polish: 😄 Kalau telat lagi, kamu traktir ya.
qwen-quoted-reply-no-context [none] -> Polish: "Aku nggak marah kok."
qwen-quoted-reply-context [bounded] -> Polish:  ⏎Aku nggak marah kok.
qwen-omitted-dia-station-no-context [none] -> Nadia jemput jejaka do stacji.
qwen-omitted-dia-station-context [bounded] -> Nanti aku jemput dia di stasiun.
qwen-particle-combo-no-context [none] -> Serius nih? Kok bisa sih?
qwen-negative-mixed-no-context [none] -> Polish: "Dla mnie, gdy to się bąk, nie ma kogo mager, ale mager. Mager, mager."
```

Conclusion: keep #112 open. The CI path now demonstrates real Qwen loading and generation on native macOS arm64, but it does not support a quality acceptance claim or Simulator validation. Further model/prompt work and the owner’s human quality review are required before using `Closes #112`.
