# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Audit attribution, English operator copy and public/private source boundaries."""
import argparse
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
from publication_audit import audit


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--public", action="store_true")
    parser.add_argument("--github", action="store_true", help="Also exclude SDK and runtime binaries")
    parser.add_argument("--git", action="store_true", help="Inspect indexed contents and all local history")
    parser.add_argument("--private-reference", type=Path, help="Reject byte-identical private files under any export name")
    args = parser.parse_args()
    result = audit(args.root, args.public or args.github, args.github, args.private_reference, args.git)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["passed"] else 1)
