#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import xml.etree.ElementTree as ET
from pathlib import Path


def text_property(node: ET.Element, name: str) -> str | None:
    prop = node.find(f"property[@name='{name}']")
    if prop is None:
        return None
    value = prop.find("string")
    return value.text if value is not None else None


def widget_record(node: ET.Element, source: Path) -> dict:
    cls = node.get("class", "")
    name = node.get("name", "")
    record = {
        "source": source.name,
        "class": cls,
        "name": name,
    }
    title = text_property(node, "title") or text_property(node, "windowTitle")
    if title:
        record["title"] = title
    children = []
    for child in node.findall("widget"):
        children.append(widget_record(child, source))
    if children:
        record["children"] = children
    actions = [item.get("name", "") for item in node.findall("addaction") if item.get("name")]
    if actions:
        record["actions"] = actions
    pages = []
    if cls in {"QTabWidget", "QToolBox", "QStackedWidget"}:
        for child in node.findall("widget"):
            pages.append({
                "name": child.get("name", ""),
                "title": text_property(child, "title") or text_property(child, "windowTitle") or child.get("name", ""),
            })
    if pages:
        record["pages"] = pages
    return record


def parse_ui(path: Path) -> dict:
    root = ET.parse(path).getroot()
    top = root.find("widget")
    actions = []
    for action in root.findall("action"):
        item = {"name": action.get("name", "")}
        title = text_property(action, "text")
        if title:
            item["title"] = title
        actions.append(item)
    return {
        "file": path.name,
        "class": (root.findtext("class") or ""),
        "root": widget_record(top, path) if top is not None else None,
        "actions": actions,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Export RPCS3 Qt Designer UI structure for the UIKit port")
    parser.add_argument("upstream_root", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    qt_root = args.upstream_root / "rpcs3/rpcs3qt"
    files = sorted(qt_root.glob("*.ui"))
    if not files:
        raise SystemExit(f"No Qt .ui files found in {qt_root}")

    model = {
        "schema": 1,
        "source": "RPCS3/rpcs3 rpcs3qt/*.ui",
        "ui_file_count": len(files),
        "documents": [parse_ui(path) for path in files],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(model, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Exported {len(files)} RPCS3 Qt UI files to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
