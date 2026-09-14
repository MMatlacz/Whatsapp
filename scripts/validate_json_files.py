#!/usr/bin/env python3
"""Validate every JSON file passed on the command line without mutating inputs."""
from __future__ import annotations

import json
import pathlib
import sys


def validate(paths: list[str]) -> int:
    failed = False
    for raw in paths:
        path = pathlib.Path(raw)
        try:
            with path.open("r", encoding="utf-8") as handle:
                json.load(handle)
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            print(f"Invalid JSON: {path}: {error}", file=sys.stderr)
            failed = True
    return 1 if failed else 0


def main() -> int:
    return validate(sys.argv[1:])


if __name__ == "__main__":
    raise SystemExit(main())
