"""Regression check: exact public revisions are allowed, evidence paths are not."""
import argparse
from pathlib import Path
import secrets
import string
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--gitleaks", default="gitleaks")
args = parser.parse_args()
config = Path(__file__).resolve().parents[2] / ".gitleaks.toml"
revision = "5d894f8cc4ef3e6c88537bf3746ed262f549da6a"
other_revision = "2fc06364715b967f1860aea9cf38778875588b17"
# A random syntactically matching noncredential; never authenticates anywhere.
noncredential = "ghp_" + "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(36))
cases = [
    ("exact public hash", "docs/native/p0.2d3-bakeoff/probe.txt", f'tokenizerRevision = "{revision}"', 0),
    ("other rule still scans evidence", "docs/native/p0.2d3-bakeoff/probe.txt", f'github_token = "{noncredential}"', 1),
    ("unknown hash still scans evidence", "docs/native/p0.2d3-bakeoff/probe.txt", f'tokenizerRevision = "{other_revision}"', 1),
    ("outside evidence still scanned", "outside.txt", f'tokenizerRevision = "{revision}"', 1),
]
for label, relative, content, expected in cases:
    with tempfile.TemporaryDirectory(prefix="whatsapp-allowlist-") as temporary:
        root = Path(temporary)
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content + "\n")
        result = subprocess.run(
            [args.gitleaks, "dir", ".", "--config", str(config), "--redact", "--no-banner"],
            cwd=root, capture_output=True, text=True,
        )
        if result.returncode != expected:
            raise RuntimeError(f"{label}: expected exit {expected}, got {result.returncode}")
        print(f"PASS {label}")
