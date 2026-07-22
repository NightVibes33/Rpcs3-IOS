#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


def nonempty_lines(path: Path) -> list[str]:
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--members", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--requested-revision", required=True)
    parser.add_argument("--resolved-commit", required=True)
    parser.add_argument("--sdk", required=True)
    args = parser.parse_args()

    sources = nonempty_lines(args.sources)
    members = nonempty_lines(args.members)
    if not sources:
        raise SystemExit("The shipping core declares no direct upstream RPCS3 sources")

    matched_objects: list[str] = []
    for source in sources:
        object_name = Path(source).name + ".o"
        if not any(object_name in member for member in members):
            raise SystemExit(
                f"Declared upstream source has no archive object: {source} ({object_name})"
            )
        matched_objects.append(object_name)

    payload = {
        "schema": 1,
        "classification": "partial-upstream",
        "capability_level": 1,
        "requested_upstream_revision": args.requested_revision,
        "resolved_upstream_commit": args.resolved_commit,
        "iphoneos_sdk": args.sdk,
        "target": "arm64-apple-ios26.0",
        "upstream_source_count": len(sources),
        "verified_upstream_object_count": len(matched_objects),
        "archive_member_count": len(members),
        "upstream_sources": sources,
        "verified_upstream_objects": matched_objects,
        "execution_capable": False,
        "ppu_interpreter_linked": False,
        "spu_interpreter_linked": False,
        "rsx_renderer_linked": False,
        "jit_linked": False,
    }
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        f"Verified {len(matched_objects)} direct upstream object(s) "
        f"inside {len(members)} archive member(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
