"""Offline MLX comparison with explicit reasoning and full raw generation evidence."""
import argparse
import importlib.metadata
import json
import os
from pathlib import Path
import resource
import subprocess
import time

from reference import digest, write_json


def messages_for(fixture, family, context_enabled):
    context = fixture.get("suppliedContext", {}) if context_enabled else {}
    text = fixture["input"]
    if family == "translategemma":
        # Context is a separately labelled experimental input strategy. Never
        # silently extract a target sentence from a whole-document translation.
        if context_enabled:
            text = "Context (do not translate):\n" + json.dumps(context, ensure_ascii=False) + "\nTarget text (translate only this):\n" + text
        return [{"role": "user", "content": [{"type": "text", "source_lang_code": "id", "target_lang_code": "pl", "text": text}]}]
    instruction = "Translate the target message from Indonesian to Polish. Return only its translation. Preserve meaning, negation, timing, slang, tone and emojis. Do not invent information."
    if context_enabled:
        instruction += " Use context only to resolve the target's meaning; do not translate the context."
    payload = {"target": text}
    if context_enabled:
        payload["context"] = context
    return [{"role": "user", "content": instruction + "\nInput data:\n" + json.dumps(payload, ensure_ascii=False)}]


def final_translation(raw, thinking):
    if not thinking:
        return raw.strip(), None
    if "</think>" not in raw:
        return None, "reasoning_not_closed"
    return raw.split("</think>", 1)[1].strip(), None


def main(args):
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    manifest = json.loads((args.model / "manifest.json").read_text())
    for artifact in manifest["artifacts"]:
        path = args.model / artifact["path"]
        if path.stat().st_size != artifact["bytes"] or digest(path) != artifact["sha256"]:
            raise ValueError("Artifact integrity failure: " + artifact["path"])
    fixtures = json.loads(args.corpus.read_text())["results"]
    if args.limit:
        fixtures = fixtures[:args.limit]
    root = Path(__file__).resolve().parents[2]
    report = {
        "schemaVersion": 1, "status": "loading", "model": manifest,
        "sourceRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "sourceDirty": bool(subprocess.check_output(["git", "-c", "core.fsmonitor=false", "status", "--porcelain"], cwd=root, text=True)),
        "scriptSHA256": digest(Path(__file__)), "helperSHA256": digest(Path(__file__).with_name("reference.py")),
        "corpusSHA256": digest(args.corpus), "offlineLocalFilesOnly": True,
        "physicalDeviceEvidence": "notRun", "qualityReview": "unreviewed",
        "runtime": {p: importlib.metadata.version(p) for p in ["mlx", "mlx-lm", "transformers", "huggingface-hub"]},
        "generation": {"thinking": args.thinking, "maxNewTokens": args.max_tokens, "temperature": args.temperature, "topP": args.top_p, "topK": args.top_k, "seed": args.seed},
        "profile": args.profile, "family": args.family, "results": [],
        "memoryScope": "isolated macOS process high-water RSS and MLX allocations; not iPhone acceptance",
    }
    write_json(args.output, report)
    import mlx.core as mx
    from mlx_lm import load, stream_generate
    from mlx_lm.sample_utils import make_sampler
    started = time.monotonic()
    model, tokenizer = load(str(args.model))
    if args.family == "translategemma":
        # The pinned snapshot names <eos> as tokenizer EOS but its native chat
        # template and observed output end turns with token 106. Stop at that
        # boundary during generation, never by trimming a completed output.
        turn_end = tokenizer.convert_tokens_to_ids("<end_of_turn>")
        if turn_end != 106:
            raise ValueError("Unexpected TranslateGemma end-of-turn token")
        tokenizer.add_eos_token("<end_of_turn>")
    report["stopTokenIDs"] = sorted(tokenizer.eos_token_ids)
    report["modelLoadSeconds"] = time.monotonic() - started
    report["status"] = "running"
    write_json(args.output, report)
    for fixture in fixtures:
        mx.random.seed(args.seed)
        messages = messages_for(fixture, args.family, args.profile == "context")
        template_kwargs = {"enable_thinking": args.thinking} if args.family == "qwen" else {}
        prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True, **template_kwargs)
        add_special = tokenizer.bos_token is None or not prompt.startswith(tokenizer.bos_token)
        prompt_ids = tokenizer.encode(prompt, add_special_tokens=add_special)
        if args.family == "translategemma" and len(prompt_ids) > 2048:
            raise ValueError("TranslateGemma documented input limit exceeded")
        raw, token_ids, last = "", [], None
        started = time.monotonic()
        first_token = None
        for event in stream_generate(model, tokenizer, prompt=prompt_ids, max_tokens=args.max_tokens,
                                     sampler=make_sampler(temp=args.temperature, top_p=args.top_p, top_k=args.top_k)):
            if first_token is None:
                first_token = time.monotonic() - started
            raw += event.text
            token_ids.append(event.token)
            last = event
        output, parse_error = final_translation(raw, args.thinking)
        row = dict(fixture)
        row.update({"actualMessages": messages, "actualInput": prompt, "inputTokenIDs": prompt_ids,
                    "rawOutput": raw, "output": output, "parseError": parse_error,
                    "outputTokenIDs": token_ids, "stopReason": last.finish_reason,
                    "hitTokenLimit": last.finish_reason == "length",
                    "generatedTokens": last.generation_tokens, "firstTokenSeconds": first_token,
                    "durationSeconds": time.monotonic() - started, "generationTokensPerSecond": last.generation_tps,
                    "mlxPeakMemoryBytes": round(last.peak_memory * 1e9)})
        report["results"].append(row)
        report["peakRSSBytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        write_json(args.output, report)
        print(f"{len(report['results'])}/{len(fixtures)} {fixture['fixtureID']} {last.finish_reason}: {output}", flush=True)
    report["status"] = "completed"
    write_json(args.output, report)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--family", choices=["qwen", "gemma", "translategemma"], required=True)
    parser.add_argument("--corpus", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--profile", choices=["source-only", "context"], default="source-only")
    parser.add_argument("--thinking", action="store_true")
    parser.add_argument("--max-tokens", type=int, default=512)
    parser.add_argument("--temperature", type=float, default=0.6)
    parser.add_argument("--top-p", type=float, default=0.95)
    parser.add_argument("--top-k", type=int, default=20)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()
    if args.thinking and args.family != "qwen":
        parser.error("Only Qwen supports this thinking comparison")
    if args.thinking and (args.max_tokens < 2048 or args.temperature == 0):
        parser.error("Thinking requires >=2048 tokens and non-greedy sampling")
    main(args)
