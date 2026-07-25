#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from pathlib import Path


# This watched Full Qt entry point also dispatches the shared Apple-mobile patch.
def run_patch(script: Path, upstream_root: str) -> None:
    subprocess.run([sys.executable, str(script), upstream_root], check=True)


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} UPSTREAM_ROOT")

    scripts = Path(__file__).resolve().parent
    upstream_root = sys.argv[1]
    run_patch(scripts / "patch-upstream-ios-full-qt-blockers-base.py", upstream_root)
    run_patch(scripts / "patch-upstream-apple-mobile-platform.py", upstream_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
