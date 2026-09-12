"""Check completeness and input/output evidence, without scoring translation quality."""
import argparse
import json
from pathlib import Path

from larger_models import final_translation, messages_for
from reference import digest


def audit(report_path, corpus_path):
    report = json.loads(report_path.read_text())
    corpus = json.loads(corpus_path.read_text())["results"]
    assert report["status"] == "completed", "Run did not complete"
    assert report["sourceDirty"] is False, "Dirty source is diagnostic only"
    assert report["corpusSHA256"] == digest(corpus_path), "Corpus hash mismatch"
    assert [r["fixtureID"] for r in report["results"]] == [r["fixtureID"] for r in corpus], "Missing, duplicate or reordered fixtures"
    assert report["offlineLocalFilesOnly"] is True
    assert report["physicalDeviceEvidence"] == "notRun", "Mac evidence cannot prove phone acceptance"
    for row, fixture in zip(report["results"], corpus):
        assert row["input"] == fixture["input"]
        assert row["actualMessages"] == messages_for(fixture, report["family"], report["profile"] == "context"), "Unexpected model input"
        assert row["generatedTokens"] == len(row["outputTokenIDs"]), "Token evidence mismatch"
        assert row["generatedTokens"] <= report["generation"]["maxNewTokens"]
        assert row["stopReason"] in ("stop", "length")
        assert row["hitTokenLimit"] == (row["stopReason"] == "length")
        if row["hitTokenLimit"]:
            assert row["generatedTokens"] == report["generation"]["maxNewTokens"]
        output, error = final_translation(row["rawOutput"], report["generation"]["thinking"])
        assert (row["output"], row["parseError"]) == (output, error), "Final output was altered"
        assert row["actualInput"] and row["inputTokenIDs"]
    return {"rows": len(corpus), "capped": sum(r["hitTokenLimit"] for r in report["results"]),
            "missingFinalTranslation": sum(not r["output"] for r in report["results"]),
            "qualityAcceptance": "not_assessed"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("corpus", type=Path)
    args = parser.parse_args()
    print(json.dumps(audit(args.report, args.corpus)))
