#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET

SUPPORTED_ROOTS = {
    "QDialog": "QDialog",
    "QWidget": "QWidget",
    "QMainWindow": "QMainWindow",
}


def identifier(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value):
        raise ValueError(f"Unsupported Qt UI class identifier: {value!r}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ui_directory", type=Path)
    parser.add_argument("output_header", type=Path)
    parser.add_argument("output_source", type=Path)
    parser.add_argument("output_cmake", type=Path)
    args = parser.parse_args()

    records: list[tuple[str, str, str, str]] = []
    skipped: list[tuple[str, str]] = []
    for path in sorted(args.ui_directory.glob("*.ui")):
        root = ET.parse(path).getroot()
        class_name = identifier((root.findtext("class") or "").strip())
        root_widget = root.find("widget")
        root_class = root_widget.attrib.get("class", "") if root_widget is not None else ""
        cpp_root = SUPPORTED_ROOTS.get(root_class)
        custom_widgets = [
            (node.findtext("class") or "").strip()
            for node in root.findall("./customwidgets/customwidget")
            if (node.findtext("class") or "").strip()
        ]
        if not cpp_root:
            skipped.append((path.name, f"unsupported root {root_class}"))
            continue
        if custom_widgets:
            skipped.append((path.name, "custom widgets: " + ", ".join(custom_widgets)))
            continue
        stem = identifier(path.stem)
        records.append((path.name, stem, class_name, cpp_root))

    for output in (args.output_header, args.output_source, args.output_cmake):
        output.parent.mkdir(parents=True, exist_ok=True)

    args.output_header.write_text(
        """#pragma once

#include <QString>
#include <QStringList>

class QWidget;

QWidget* RPCS3CreateCompiledUi(const QString& fileName, QWidget* parent = nullptr);
QStringList RPCS3CompiledUiFiles();
""",
        encoding="utf-8",
    )

    includes = "\n".join(f'#include "ui_{stem}.h"' for _, stem, _, _ in records)
    branches: list[str] = []
    names: list[str] = []
    for file_name, _, class_name, cpp_root in records:
        branches.append(
            f'''    if (fileName == QStringLiteral("{file_name}"))
    {{
        auto* widget = new {cpp_root}(parent);
        Ui::{class_name} ui;
        ui.setupUi(widget);
        return widget;
    }}'''
        )
        names.append(f'QStringLiteral("{file_name}")')

    source = f'''#include "RPCS3QtUiFactory.h"

#include <QDialog>
#include <QMainWindow>
#include <QWidget>

{includes}

QWidget* RPCS3CreateCompiledUi(const QString& fileName, QWidget* parent)
{{
{chr(10).join(branches)}
    return nullptr;
}}

QStringList RPCS3CompiledUiFiles()
{{
    return {{{", ".join(names)}}};
}}
'''
    args.output_source.write_text(source, encoding="utf-8")

    cmake_lines = ["set(RPCS3_COMPILED_UI_FILES"]
    cmake_lines.extend(f'    "${{CMAKE_CURRENT_LIST_DIR}}/ui/{file_name}"' for file_name, _, _, _ in records)
    cmake_lines.append(")")
    args.output_cmake.write_text("\n".join(cmake_lines) + "\n", encoding="utf-8")

    print(f"Generated Qt UI factory for {len(records)} forms")
    for file_name, reason in skipped:
        print(f"Skipped {file_name}: {reason}")
    if "main_window.ui" not in {item[0] for item in records}:
        raise SystemExit("main_window.ui was not included in the compiled UI factory")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
