#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import xml.etree.ElementTree as ET
from pathlib import Path


VALUE_TAGS = ("string", "cstring", "number", "double", "bool", "enum", "set")
CONTAINER_TAGS = {"layout", "item"}
PAGE_CLASSES = {"QTabWidget", "QToolBox", "QStackedWidget"}


def value_text(container: ET.Element | None) -> str | None:
    if container is None:
        return None
    for tag in VALUE_TAGS:
        value = container.find(tag)
        if value is not None and value.text is not None:
            return value.text
    return None


def property_text(node: ET.Element, name: str) -> str | None:
    return value_text(node.find(f"property[@name='{name}']"))


def attribute_text(node: ET.Element, name: str) -> str | None:
    return value_text(node.find(f"attribute[@name='{name}']"))


def logical_child_widgets(node: ET.Element):
    """Yield widgets contained by this widget, including those wrapped in layouts/items.

    Qt Designer places most controls under layout/item nodes rather than directly under
    their parent widget. Stop descending after finding a widget so each widget appears
    exactly once in the exported hierarchy.
    """
    for child in list(node):
        if child.tag == "widget":
            yield child
        elif child.tag in CONTAINER_TAGS:
            yield from logical_child_widgets(child)


def item_titles(node: ET.Element) -> list[str]:
    values: list[str] = []
    for item in node.findall("item"):
        title = property_text(item, "text")
        if title:
            values.append(title)
    return values


def widget_title(node: ET.Element) -> str | None:
    return (
        attribute_text(node, "title")
        or attribute_text(node, "label")
        or property_text(node, "title")
        or property_text(node, "windowTitle")
    )


def widget_record(node: ET.Element, source: Path) -> dict:
    cls = node.get("class", "")
    name = node.get("name", "")
    record: dict = {
        "source": source.name,
        "class": cls,
        "name": name,
    }

    title = widget_title(node)
    if title:
        record["title"] = title

    for output_key, property_name in (
        ("text", "text"),
        ("placeholder", "placeholderText"),
        ("tool_tip", "toolTip"),
        ("status_tip", "statusTip"),
        ("whats_this", "whatsThis"),
        ("enabled", "enabled"),
        ("checked", "checked"),
        ("current_index", "currentIndex"),
        ("minimum", "minimum"),
        ("maximum", "maximum"),
        ("value", "value"),
        ("orientation", "orientation"),
    ):
        value = property_text(node, property_name)
        if value is not None:
            record[output_key] = value

    items = item_titles(node)
    if items:
        record["items"] = items

    children = [widget_record(child, source) for child in logical_child_widgets(node)]
    if children:
        record["children"] = children

    actions = [item.get("name", "") for item in node.findall("addaction") if item.get("name")]
    if actions:
        record["actions"] = actions

    if cls in PAGE_CLASSES:
        pages = []
        for child in logical_child_widgets(node):
            pages.append(
                {
                    "name": child.get("name", ""),
                    "title": widget_title(child) or child.get("name", ""),
                }
            )
        if pages:
            record["pages"] = pages

    return record


def action_record(action: ET.Element) -> dict:
    item: dict = {"name": action.get("name", "")}
    for output_key, property_name in (
        ("title", "text"),
        ("tool_tip", "toolTip"),
        ("status_tip", "statusTip"),
        ("shortcut", "shortcut"),
        ("checkable", "checkable"),
        ("checked", "checked"),
        ("enabled", "enabled"),
    ):
        value = property_text(action, property_name)
        if value is not None:
            item[output_key] = value
    return item


def parse_ui(path: Path) -> dict:
    root = ET.parse(path).getroot()
    top = root.find("widget")
    return {
        "file": path.name,
        "class": root.findtext("class") or "",
        "root": widget_record(top, path) if top is not None else None,
        "actions": [action_record(action) for action in root.findall("action")],
    }


def count_nodes(node: dict | None) -> int:
    if not node:
        return 0
    return 1 + sum(count_nodes(child) for child in node.get("children", []))


def main() -> int:
    parser = argparse.ArgumentParser(description="Export RPCS3 Qt Designer UI structure for the UIKit port")
    parser.add_argument("upstream_root", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    qt_root = args.upstream_root / "rpcs3/rpcs3qt"
    files = sorted(qt_root.glob("*.ui"))
    if not files:
        raise SystemExit(f"No Qt .ui files found in {qt_root}")

    documents = [parse_ui(path) for path in files]
    model = {
        "schema": 2,
        "source": "RPCS3/rpcs3 rpcs3qt/*.ui",
        "ui_file_count": len(files),
        "widget_count": sum(count_nodes(document.get("root")) for document in documents),
        "documents": documents,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(model, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        f"Exported {model['ui_file_count']} RPCS3 Qt UI files and "
        f"{model['widget_count']} nested widgets to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
