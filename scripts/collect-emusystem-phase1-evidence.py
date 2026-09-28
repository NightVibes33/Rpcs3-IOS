#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shlex
from pathlib import Path


def output_token(entry: dict) -> Path | None:
    output = entry.get("output")
    if output:
        return Path(output)

    command = entry.get("command")
    if command:
        parts = shlex.split(command)
    else:
        parts = list(entry.get("arguments") or [])
    for index, part in enumerate(parts[:-1]):
        if part == "-o":
            return Path(parts[index + 1])
    return None


def resolve_output(entry: dict, build_root: Path) -> Path | None:
    token = output_token(entry)
    if token is None:
        return None
    if token.is_absolute():
        return token

    directory = Path(entry.get("directory") or build_root)
    candidates = [directory / token, build_root / token]
    for candidate in candidates:
        if candidate.is_file():
            return candidate

    # Some CMake compile databases use a target-relative output while setting
    # `directory` to that target's subdirectory. Joining both duplicates the
    # path (for example rpcs3/Emu/rpcs3/Emu/CMakeFiles/...). Resolve the real
    # object by its unique suffix before reporting it absent.
    suffix = token.as_posix()
    matches = [path for path in build_root.rglob(token.name) if path.as_posix().endswith(suffix)]
    if len(matches) == 1:
        return matches[0]

    return candidates[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compile-commands", type=Path, required=True)
    parser.add_argument("--build-root", type=Path, required=True)
    parser.add_argument("--build-status", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if not args.compile_commands.is_file():
        raise SystemExit(f"compile_commands.json was not generated: {args.compile_commands}")

    entries = json.loads(args.compile_commands.read_text(encoding="utf-8"))
    emulator_entries = []
    loader_entries = []
    system_entry = None
    groups = {"system": 0, "ppu": 0, "spu": 0, "lv2": 0, "rsx": 0, "vfs": 0, "loader": 0}

    for entry in entries:
        source = str(entry.get("file") or "").replace("\\", "/")
        lower = source.lower()
        if "/rpcs3/Loader/" in source:
            loader_entries.append(entry)
            groups["loader"] += 1
        if "/rpcs3/Emu/" not in source:
            continue

        emulator_entries.append(entry)
        if source.endswith("/rpcs3/Emu/System.cpp"):
            system_entry = entry
            groups["system"] += 1
        if "/cell/ppu" in lower:
            groups["ppu"] += 1
        if "/cell/spu" in lower or "/cell/rawspu" in lower:
            groups["spu"] += 1
        if "/cell/lv2/" in lower:
            groups["lv2"] += 1
        if "/rsx/" in lower:
            groups["rsx"] += 1
        if source.endswith("/rpcs3/Emu/VFS.cpp") or source.endswith("/rpcs3/Emu/vfs_config.cpp"):
            groups["vfs"] += 1

    if system_entry is None:
        raise SystemExit("The real rpcs3_emu compile database does not contain rpcs3/Emu/System.cpp")

    object_path = resolve_output(system_entry, args.build_root)
    object_built = bool(object_path and object_path.is_file())
    payload = {
        "schema": 1,
        "roadmap_phase": 1,
        "target": "rpcs3_emu",
        "classification": "upstream-graph-compile-probe",
        "system_cpp_configured": True,
        "system_cpp_object": str(object_path) if object_path else None,
        "system_cpp_object_built": object_built,
        "configured_emu_source_count": len(emulator_entries),
        "configured_loader_source_count": len(loader_entries),
        "configured_source_groups": groups,
        "rpcs3_emu_build_status": args.build_status,
        "rpcs3_emu_target_compiled": args.build_status == 0,
        "execution_capable": False,
        "note": (
            "Compiling System.cpp or rpcs3_emu proves direct upstream source integration only. "
            "Physical-device Emu.System initialization and guest execution require separate runtime evidence."
        ),
    }
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "Phase 1 evidence: System.cpp configured="
        f"yes, object_built={'yes' if object_built else 'no'}, "
        f"emu_sources={len(emulator_entries)}, loader_sources={len(loader_entries)}, "
        f"rpcs3_emu_status={args.build_status}"
    )
    if args.build_status == 0 and not object_built:
        raise SystemExit("rpcs3_emu succeeded but the System.cpp object could not be verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
