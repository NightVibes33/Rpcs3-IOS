#!/usr/bin/env python3
from __future__ import annotations

import os
import signal
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <seconds> <command> [args...]", file=sys.stderr)
        return 64

    try:
        seconds = float(sys.argv[1])
    except ValueError:
        print(f"invalid timeout: {sys.argv[1]}", file=sys.stderr)
        return 64

    command = sys.argv[2:]
    process = subprocess.Popen(
        command,
        start_new_session=True,
        stdout=sys.stdout,
        stderr=sys.stderr,
        env=os.environ.copy(),
    )
    try:
        return process.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        print(f"command timed out after {seconds:g}s: {' '.join(command)}", file=sys.stderr)
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=10)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        return 124


if __name__ == "__main__":
    raise SystemExit(main())
