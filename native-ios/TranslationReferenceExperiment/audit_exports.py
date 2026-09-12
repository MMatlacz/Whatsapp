"""Read-only source/corpus/provenance checks for the archived reference runs."""
import hashlib
import json
from pathlib import Path
import subprocess
from reference import MODELS

root = Path(__file__).resolve().parents[2]
directory = root / "docs/native/p0.2d4-reference-controls"
full_corpus = root / "docs/native/p0.2d3-bakeoff/candidates/qwen3.5-0.8b-4bit/report.json"
context_corpus = directory / "context-corpus.json"
sha = lambda data: hashlib.sha256(data).hexdigest()
expected_context = json.loads(full_corpus.read_text())
expected_context["results"] = [r for r in expected_context["results"] if r["contextMode"] == "bounded"]
assert json.loads(context_corpus.read_text()) == expected_context

reports = sorted(p for p in directory.glob("*.json") if p != context_corpus)
assert len(reports) == 10
total = 0
for path in reports:
    report = json.loads(path.read_text())
    assert report["status"] == "completed", path.name
    assert report["sourceDirty"] is False, path.name
    assert report["physicalDeviceEvidence"] == "notRun", path.name
    assert report["offlineLocalFilesOnly"] is True, path.name
    model_id = (
        "m2m100" if path.name.startswith("m2m100") else
        "nllb" if path.name.startswith("nllb") else
        "qwen" if path.name.startswith("qwen-float32") else "qwen-mlx"
    )
    assert report["model"]["repository"] == MODELS[model_id][0], path.name
    assert report["model"]["revision"] == MODELS[model_id][1], path.name
    assert report["generation"]["numBeams"] == (5 if "beam5" in path.name else 1), path.name
    script = subprocess.check_output(
        ["git", "show", report["sourceRevision"] + ":native-ios/TranslationReferenceExperiment/reference.py"],
        cwd=root,
    )
    assert sha(script) == report["scriptSHA256"], path.name
    corpus = context_corpus if report["profile"] == "context" else full_corpus
    assert sha(corpus.read_bytes()) == report["corpusSHA256"], path.name
    fixtures = json.loads(corpus.read_text())["results"]
    assert len(report["results"]) == len(fixtures), path.name
    for result, fixture in zip(report["results"], fixtures, strict=True):
        for key in ["fixtureID", "input", "intendedMeaning", "preservationNotes", "suppliedContext"]:
            assert result[key] == fixture[key], (path.name, key)
        if report["profile"] == "source-only" and "facebook/" in report["model"]["repository"]:
            assert result["actualInput"] == result["input"], path.name
    if report["profile"] == "source-only":
        seen = {}
        for result in report["results"]:
            if result["semanticCaseID"] in seen:
                assert seen[result["semanticCaseID"]] == result["output"], path.name
            seen[result["semanticCaseID"]] = result["output"]
        assert len(seen) == 24
    if path.name.startswith("nllb-") and "invalid" not in path.name:
        check = report["languageTokenCheck"]
        assert check["tokenizerClass"] == "NllbTokenizer"
        assert check["probeTokens"][0] == "ind_Latn"
        assert check["sourceToken"] != check["targetToken"]
    total += len(report["results"])
    print(f"PASS {path.name}: {len(report['results'])} rows, clean source and matching hashes")
assert total == 248
print("248 raw rows verified; 32 invalid-tokenizer rows are excluded from quality evidence.")
