#!/usr/bin/env python3
"""Deterministic PKGi v1.3.0 PKG install smoke test.

This mirrors RPCS3's debug-PKG stream cipher closely enough to validate and
extract the exact open-source PKGi fixture without linking host RPCS3. It is
not a renderer/device test; it proves the package is authentic, decryptable,
installable to the expected VFS path, and exposes a valid PS3 SELF boot target.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import struct
import sys
import tempfile
from typing import Any

EXPECTED_SHA256 = "259b0b635399e2c3e92ad3152de167ca7b79389e1e3c965f43912b4d23b5e701"
EXPECTED_CONTENT_ID = "UP0001-NP00PKGI3_00-0000000000000000"
EXPECTED_TITLE_ID = "NP00PKGI3"
EXPECTED_TITLE = "PKGi PS3"
EXPECTED_VERSION = "01.30"
EXPECTED_CATEGORY = "CB"
EXPECTED_FILE_COUNT = 17
PKG_MAGIC = b"\x7fPKG"
SFO_MAGIC = 0x46535000
SELF_MAGIC = b"SCE\x00"
PKG_RELEASE_TYPE_DEBUG = 0x0000
PKG_PLATFORM_TYPE_PS3 = 0x0001
PKG_CONTENT_TYPE_GAME_EXEC = 0x05
PKG_ENTRY_FOLDER = 0x04
PKG_ENTRY_TYPE_MASK = 0xFF


class SmokeFailure(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SmokeFailure(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def c_string(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("utf-8", "strict")


def parse_sfo(data: bytes) -> dict[str, Any]:
    require(len(data) >= 20, "PARAM.SFO is truncated")
    magic, version, key_table, data_table, count = struct.unpack_from("<IIIII", data, 0)
    require(magic == SFO_MAGIC, f"PARAM.SFO magic is invalid: 0x{magic:08x}")
    require(version == 0x101, f"Unexpected PARAM.SFO version: 0x{version:x}")
    require(20 + count * 16 <= len(data), "PARAM.SFO index table is truncated")

    values: dict[str, Any] = {}
    for index in range(count):
        entry_offset = 20 + index * 16
        key_offset, fmt, length, max_length, value_offset = struct.unpack_from(
            "<HHIII", data, entry_offset
        )
        require(length <= max_length, "PARAM.SFO entry length exceeds max length")
        key_start = key_table + key_offset
        require(key_start < len(data), "PARAM.SFO key offset is outside the file")
        key_end = data.find(b"\0", key_start)
        require(key_end >= 0, "PARAM.SFO key is not NUL terminated")
        key = data[key_start:key_end].decode("utf-8", "strict")
        start = data_table + value_offset
        end = start + length
        require(end <= len(data), f"PARAM.SFO value for {key} is truncated")
        raw = data[start:end]
        if fmt in (0x0004, 0x0204):
            value: Any = raw.rstrip(b"\0").decode("utf-8", "strict")
        elif fmt == 0x0404:
            require(len(raw) >= 4, f"PARAM.SFO integer {key} is truncated")
            value = struct.unpack_from("<I", raw, 0)[0]
        else:
            value = raw.hex()
        values[key] = value
    return values


class DebugPkg:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.data = path.read_bytes()
        require(len(self.data) >= 0xC0, "PKG is smaller than the PS3 header")
        require(self.data[:4] == PKG_MAGIC, "PKG magic is invalid")

        self.pkg_type, self.platform = struct.unpack_from(">HH", self.data, 4)
        (
            self.meta_offset,
            self.meta_count,
            self.meta_size,
            self.file_count,
        ) = struct.unpack_from(">IIII", self.data, 8)
        self.pkg_size, self.data_offset, self.data_size = struct.unpack_from(">QQQ", self.data, 24)
        self.content_id = c_string(self.data[48:96])
        self.qa0 = self.data[96:104]
        self.qa1 = self.data[104:112]

        require(self.pkg_type == PKG_RELEASE_TYPE_DEBUG, "Fixture is not a debug PKG")
        require(self.platform == PKG_PLATFORM_TYPE_PS3, "Fixture is not a PS3 PKG")
        require(self.pkg_size == len(self.data), "PKG header size does not match file size")
        require(self.data_offset + self.data_size <= len(self.data), "Encrypted PKG data exceeds file")
        require(self.file_count == EXPECTED_FILE_COUNT, f"Expected {EXPECTED_FILE_COUNT} entries, got {self.file_count}")
        require(self.content_id == EXPECTED_CONTENT_ID, f"Unexpected content ID: {self.content_id}")

    def decrypt(self, offset: int, size: int) -> bytes:
        require(offset >= 0 and size >= 0, "Negative PKG range")
        start = self.data_offset + offset
        end = start + size
        require(end <= len(self.data), "Encrypted PKG range exceeds file")
        output = bytearray(self.data[start:end])
        blocks = (len(output) + 15) // 16
        for block_index in range(blocks):
            counter = offset // 16 + block_index
            sha_input = self.qa0 + self.qa0 + self.qa1 + self.qa1 + (b"\0" * 24) + struct.pack(">Q", counter)
            key_stream = hashlib.sha1(sha_input).digest()
            base = block_index * 16
            for byte_index in range(min(16, len(output) - base)):
                output[base + byte_index] ^= key_stream[byte_index]
        return bytes(output)

    def metadata(self) -> dict[int, bytes]:
        require(self.meta_offset + self.meta_size <= len(self.data), "PKG metadata exceeds file")
        cursor = self.meta_offset
        result: dict[int, bytes] = {}
        for _ in range(self.meta_count):
            require(cursor + 8 <= len(self.data), "PKG metadata packet header is truncated")
            packet_id, size = struct.unpack_from(">II", self.data, cursor)
            cursor += 8
            require(cursor + size <= len(self.data), "PKG metadata packet is truncated")
            result[packet_id] = self.data[cursor:cursor + size]
            cursor += size
        return result

    def entries(self) -> list[dict[str, Any]]:
        table_size = self.file_count * 32
        table = self.decrypt(0, table_size)
        entries: list[dict[str, Any]] = []
        for index in range(self.file_count):
            base = index * 32
            name_offset, name_size = struct.unpack_from(">II", table, base)
            file_offset, file_size = struct.unpack_from(">QQ", table, base + 8)
            entry_type, pad = struct.unpack_from(">II", table, base + 24)
            require(name_size <= 256, f"Entry {index} name is too large")
            require(name_offset + name_size <= self.data_size, f"Entry {index} name exceeds data")
            require(file_offset + file_size <= self.data_size, f"Entry {index} payload exceeds data")
            name = self.decrypt(name_offset, name_size).rstrip(b"\0").decode("utf-8", "strict")
            relative = PurePosixPath(name)
            require(not relative.is_absolute(), f"Absolute path in PKG: {name}")
            require(".." not in relative.parts, f"Path traversal in PKG: {name}")
            entries.append(
                {
                    "index": index,
                    "name": name,
                    "name_offset": name_offset,
                    "file_offset": file_offset,
                    "file_size": file_size,
                    "entry_type": entry_type,
                    "pad": pad,
                }
            )
        return entries

    def extract(self, destination: Path) -> list[dict[str, Any]]:
        destination.mkdir(parents=True, exist_ok=True)
        entries = self.entries()
        destination_resolved = destination.resolve()
        for entry in entries:
            target = destination.joinpath(*PurePosixPath(entry["name"]).parts)
            resolved_parent = target.parent.resolve()
            require(
                resolved_parent == destination_resolved or destination_resolved in resolved_parent.parents,
                f"Extraction escaped destination: {entry['name']}",
            )
            base_type = entry["entry_type"] & PKG_ENTRY_TYPE_MASK
            if base_type == PKG_ENTRY_FOLDER:
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            payload = self.decrypt(entry["file_offset"], entry["file_size"])
            target.write_bytes(payload)
            require(target.stat().st_size == entry["file_size"], f"Short write for {entry['name']}")
        return entries


def run(pkg_path: Path, output_path: Path | None, extract_root: Path | None) -> dict[str, Any]:
    require(pkg_path.is_file(), f"PKG fixture does not exist: {pkg_path}")
    digest = sha256_file(pkg_path)
    require(digest == EXPECTED_SHA256, f"PKGi fixture SHA-256 mismatch: {digest}")

    package = DebugPkg(pkg_path)
    metadata = package.metadata()
    require(int.from_bytes(metadata.get(2, b""), "big") == PKG_CONTENT_TYPE_GAME_EXEC, "PKG is not GameExec content")

    temporary: tempfile.TemporaryDirectory[str] | None = None
    if extract_root is None:
        temporary = tempfile.TemporaryDirectory(prefix="rpcs3-pkgi-smoke-")
        root = Path(temporary.name)
    else:
        root = extract_root
        if root.exists():
            shutil.rmtree(root)
        root.mkdir(parents=True)

    install_dir = root / "dev_hdd0" / "game" / EXPECTED_TITLE_ID
    entries = package.extract(install_dir)
    entry_names = {entry["name"] for entry in entries}
    require("PARAM.SFO" in entry_names, "PKG does not contain PARAM.SFO")
    require("USRDIR/EBOOT.BIN" in entry_names, "PKG does not contain USRDIR/EBOOT.BIN")
    require("ICON0.PNG" in entry_names, "PKG does not contain ICON0.PNG")

    sfo_path = install_dir / "PARAM.SFO"
    eboot_path = install_dir / "USRDIR" / "EBOOT.BIN"
    icon_path = install_dir / "ICON0.PNG"
    sfo = parse_sfo(sfo_path.read_bytes())
    require(sfo.get("TITLE_ID") == EXPECTED_TITLE_ID, f"Unexpected TITLE_ID: {sfo.get('TITLE_ID')}")
    require(sfo.get("TITLE") == EXPECTED_TITLE, f"Unexpected TITLE: {sfo.get('TITLE')}")
    require(sfo.get("VERSION") == EXPECTED_VERSION, f"Unexpected VERSION: {sfo.get('VERSION')}")
    require(sfo.get("APP_VER") == EXPECTED_VERSION, f"Unexpected APP_VER: {sfo.get('APP_VER')}")
    require(sfo.get("CATEGORY") == EXPECTED_CATEGORY, f"Unexpected CATEGORY: {sfo.get('CATEGORY')}")
    require(sfo.get("BOOTABLE") == 1, "PARAM.SFO does not mark the title bootable")
    require(eboot_path.stat().st_size == 1604208, "Unexpected EBOOT.BIN size")
    require(eboot_path.read_bytes()[:4] == SELF_MAGIC, "EBOOT.BIN is not an SCE SELF")
    require(icon_path.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n", "ICON0.PNG is invalid")

    evidence = {
        "result": "pass",
        "fixture": pkg_path.name,
        "sha256": digest,
        "pkg_type": "debug",
        "platform": "PS3",
        "content_id": package.content_id,
        "content_type": PKG_CONTENT_TYPE_GAME_EXEC,
        "file_count": package.file_count,
        "title": sfo["TITLE"],
        "title_id": sfo["TITLE_ID"],
        "version": sfo["VERSION"],
        "category": sfo["CATEGORY"],
        "bootable": sfo["BOOTABLE"],
        "install_path": f"/dev_hdd0/game/{EXPECTED_TITLE_ID}",
        "boot_path": f"/dev_hdd0/game/{EXPECTED_TITLE_ID}/USRDIR/EBOOT.BIN",
        "eboot_size": eboot_path.stat().st_size,
        "eboot_sha256": sha256_file(eboot_path),
        "eboot_magic": eboot_path.read_bytes()[:4].hex(),
        "entries": [
            {
                "name": entry["name"],
                "size": entry["file_size"],
                "type": f"0x{entry['entry_type']:08x}",
            }
            for entry in entries
        ],
        "scope": "PKG authenticity + decrypt + install-tree + PARAM.SFO + SELF boot-target contract",
        "not_proven": "physical iOS rendering, touch/controller input, audio, networking, or sustained gameplay",
    }

    if output_path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if temporary is not None:
        temporary.cleanup()
    return evidence


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pkg", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--extract-root", type=Path)
    args = parser.parse_args()
    try:
        evidence = run(args.pkg, args.output, args.extract_root)
    except (OSError, UnicodeError, struct.error, SmokeFailure) as error:
        print(f"PKGi smoke test failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(evidence, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
