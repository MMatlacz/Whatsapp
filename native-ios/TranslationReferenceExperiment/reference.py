"""Diagnostic reference inference; provisioning is a separate explicit command."""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import resource
import subprocess
import time

MODELS = {
    "m2m100": ("facebook/m2m100_418M", "55c2e61bbf05dfb8d7abccdc3fae6fc8512fd636", "MIT"),
    "nllb": ("facebook/nllb-200-distilled-600M", "f8d333a098d19b4fd9a8b18f94170487ad3f821d", "CC-BY-NC-4.0; research only"),
    "qwen": ("Qwen/Qwen3.5-0.8B", "2fc06364715b967f1860aea9cf38778875588b17", "Apache-2.0"),
    "qwen-mlx": ("mlx-community/Qwen3.5-0.8B-MLX-4bit", "5d894f8cc4ef3e6c88537bf3746ed262f549da6a", "Apache-2.0"),
}


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def provision(args):
    from huggingface_hub import snapshot_download

    repo, revision, license_name = MODELS[args.model]
    directory = args.models / args.model
    snapshot_download(
        repo, revision=revision, token=False, local_dir=directory,
        allow_patterns=["*.json", "*.jinja", "*.txt", "*.model", "*.safetensors", "pytorch_model.bin", "README.md", "LICENSE"],
        max_workers=2,
    )
    artifacts = [
        {"path": p.name, "bytes": p.stat().st_size, "sha256": digest(p)}
        for p in sorted(directory.iterdir()) if p.is_file() and p.name != "manifest.json"
    ]
    write_json(directory / "manifest.json", {
        "repository": repo, "revision": revision, "license": license_name, "artifacts": artifacts,
    })
    print(f"Provisioned {args.model}: {sum(a['bytes'] for a in artifacts)} bytes", flush=True)


def run(args):
    # Set these before importing either inference stack. There is no Hub ID in
    # any inference load call, and no acquisition fallback.
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    directory = args.models / args.model
    manifest = json.loads((directory / "manifest.json").read_text())
    for artifact in manifest["artifacts"]:
        path = directory / artifact["path"]
        if path.stat().st_size != artifact["bytes"] or digest(path) != artifact["sha256"]:
            raise ValueError(f"Artifact integrity failure: {artifact['path']}")
    records = json.loads(args.corpus.read_text())["results"]
    if args.limit:
        records = records[:args.limit]
    root = Path(__file__).resolve().parents[2]
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "-c", "core.fsmonitor=false", "status", "--porcelain"], cwd=root, text=True))
    report = {
        "schemaVersion": 1, "sourceRevision": revision, "sourceDirty": dirty,
        "scriptSHA256": digest(Path(__file__)), "corpusSHA256": digest(args.corpus),
        "model": manifest, "profile": args.profile,
        "runtime": {p: importlib.metadata.version(p) for p in ["torch", "transformers", "mlx", "mlx-lm", "tokenizers", "sentencepiece", "huggingface-hub"]},
        "platform": platform.system() + "-" + platform.machine(), "device": args.device,
        "physicalDeviceEvidence": "notRun", "offlineLocalFilesOnly": True,
        "generation": {"maxNewTokens": 128, "doSample": False, "numBeams": args.beams},
        "qualityReview": "unreviewed", "status": "running", "results": [],
    }
    write_json(args.output, report)
    started = time.monotonic()
    if args.model == "qwen-mlx":
        from mlx_lm import load, generate
        from mlx_lm.sample_utils import make_sampler
        model, tokenizer = load(str(directory))
        report["dtype"] = "snapshot-4bit"

        def translate(text):
            prompt = tokenizer.apply_chat_template(
                [{"role": "user", "content": text}], tokenize=False,
                add_generation_prompt=True, enable_thinking=False,
            )
            return generate(model, tokenizer, prompt=prompt, max_tokens=128,
                            sampler=make_sampler(temp=0), verbose=False), prompt, None
    else:
        import torch
        from transformers import (
            AutoTokenizer,
            AutoModelForSeq2SeqLM,
            NllbTokenizer,
            Qwen3_5ForConditionalGeneration,
        )
        torch.set_num_threads(4)
        tokenizer = (
            NllbTokenizer.from_pretrained(directory, src_lang="ind_Latn", local_files_only=True)
            if args.model == "nllb"
            else AutoTokenizer.from_pretrained(directory, local_files_only=True)
        )
        dtype = torch.float32 if args.device == "cpu" else torch.bfloat16
        cls = Qwen3_5ForConditionalGeneration if args.model == "qwen" else AutoModelForSeq2SeqLM
        model = cls.from_pretrained(directory, local_files_only=True, dtype=dtype).to(args.device).eval()
        report["dtype"] = str(dtype)
        if args.model == "m2m100":
            tokenizer.src_lang = "id"
            target_token = tokenizer.get_lang_id("pl")
        elif args.model == "nllb":
            tokenizer.src_lang = "ind_Latn"
            target_token = tokenizer.convert_tokens_to_ids("pol_Latn")
        if args.model in ["nllb", "m2m100"]:
            source_token = (tokenizer.convert_tokens_to_ids("ind_Latn")
                            if args.model == "nllb" else tokenizer.get_lang_id("id"))
            probe = tokenizer("Aku sudah sampai di rumah.")["input_ids"]
            if probe[0] != source_token or source_token == tokenizer.unk_token_id or target_token == tokenizer.unk_token_id:
                raise ValueError("Invalid source/target language token configuration")
            report["languageTokenCheck"] = {
                "tokenizerClass": type(tokenizer).__name__, "sourceToken": source_token,
                "targetToken": target_token, "probeTokens": tokenizer.convert_ids_to_tokens(probe),
            }

        def translate(text):
            if args.model == "qwen":
                text = tokenizer.apply_chat_template(
                    [{"role": "user", "content": text}], tokenize=False,
                    add_generation_prompt=True, enable_thinking=False,
                )
            inputs = tokenizer(text, return_tensors="pt").to(args.device)
            kwargs = {} if args.model == "qwen" else {"forced_bos_token_id": target_token}
            with torch.inference_mode():
                ids = model.generate(**inputs, max_new_tokens=128, do_sample=False, num_beams=args.beams, **kwargs)[0]
            output_ids = ids[inputs.input_ids.shape[1]:] if args.model == "qwen" else ids[1:]
            return tokenizer.decode(output_ids, skip_special_tokens=True), text, output_ids.tolist()
    report["modelLoadSeconds"] = time.monotonic() - started
    for fixture in records:
        text = fixture["input"]
        context = fixture.get("suppliedContext", {})
        if args.model.startswith("qwen"):
            text = "Translate from Indonesian to Polish. Return only the translation.\n" + text
            if args.profile == "context":
                text = "Use the following context only to interpret the target, not as text to translate:\n" + json.dumps(context, ensure_ascii=False) + "\n" + text
        elif args.profile == "context":
            # Explicit exploratory document input: output includes context.
            # No fabricated target extraction or chat-contract pass is claimed.
            bodies = [turn["body"] for turn in context.get("recentTurns", [])]
            if context.get("quotedTurn"):
                bodies.append(context["quotedTurn"]["body"])
            text = "\n".join(bodies + [text])
        started = time.monotonic()
        output, actual_input, ids = translate(text)
        record = {k: fixture[k] for k in ["fixtureID", "semanticCaseID", "input", "intendedMeaning", "preservationNotes", "contextMode", "suppliedContext"]}
        record.update({"actualInput": actual_input, "output": output,
                       "durationSeconds": time.monotonic() - started, "outputTokenIDs": ids,
                       "hitTokenLimit": len(ids) >= 128 if ids is not None else None})
        report["results"].append(record)
        write_json(args.output, report)
        print(f"{len(report['results'])}/{len(records)} {fixture['fixtureID']}: {output}", flush=True)
    report["status"] = "completed"
    report["peakRSSBytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    report["memoryScope"] = "isolated macOS process high-water RSS; not iPhone acceptance"
    write_json(args.output, report)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["provision", "run"])
    parser.add_argument("--model", choices=MODELS, required=True)
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--corpus", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--profile", choices=["source-only", "context"], default="source-only")
    parser.add_argument("--device", choices=["cpu", "mps"], default="cpu")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--beams", type=int, choices=[1, 5], default=1)
    args = parser.parse_args()
    if args.command == "run" and (args.corpus is None or args.output is None):
        parser.error("run requires --corpus and --output")
    if args.model.startswith("qwen") and args.beams != 1:
        parser.error("the Qwen controls use greedy decoding (--beams 1)")
    provision(args) if args.command == "provision" else run(args)
