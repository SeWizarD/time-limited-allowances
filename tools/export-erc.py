#!/usr/bin/env python3
"""Write SPEC.md and the reference contracts into an ethereum/ERCs checkout, in that repo's format.

usage: tools/export-erc.py <ERCs checkout> [erc number]
"""
import re
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
ercs = Path(sys.argv[1])
number = sys.argv[2] if len(sys.argv) > 2 else None
slug = f"erc-{number}" if number else "erc-draft_time_limited_allowances"

spec = (root / "SPEC.md").read_text()
if number:
    spec = spec.replace("---\ntitle:", f"---\neip: {number}\ntitle:", 1)
spec = re.sub(r"\]\(https://eips\.ethereum\.org/EIPS/eip-(\d+)\)", r"](./eip-\1.md)", spec)
spec = spec.replace("(https://creativecommons.org/publicdomain/zero/1.0/)", "(../LICENSE.md)")
for src in ["src/ERC20Expiring.sol", "src/interfaces/IERC20Expiring.sol", "src/ExpiringToken.sol"]:
    spec = spec.replace(f"({src})", f"(../assets/{slug}/{Path(src).name})")

(ercs / "ERCS" / f"{slug}.md").write_text(spec)
assets = ercs / "assets" / slug
assets.mkdir(parents=True, exist_ok=True)
for src in ["src/ERC20Expiring.sol", "src/interfaces/IERC20Expiring.sol", "src/ExpiringToken.sol"]:
    text = (root / src).read_text().replace('"./interfaces/IERC20Expiring.sol"', '"./IERC20Expiring.sol"')
    (assets / Path(src).name).write_text(text)
print(ercs / "ERCS" / f"{slug}.md")
