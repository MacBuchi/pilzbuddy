#!/usr/bin/env python3
"""Adapts the generated Protomaps style for vector_tile_renderer.

The style from @protomaps/basemaps uses MapLibre expressions the Flutter
renderer (vector_tile_renderer 6.x) does not support; affected layers were
silently dropped — no labels, gray landcover. This script rewrites them:

- ["in", ["get", k], ["literal", [...]]]  ->  legacy ["in", k, ...]
  (same for the negated form via ["!", ...])
- complex "format"/multi-script text-field expressions
  -> ["coalesce", ["get", "name:de"], ["get", "name"]]
- drops icon-based layers (shields, oneway arrows) — we ship no sprites.

Usage (after regenerating the style with @protomaps/basemaps):
    python3 tool/transform_map_style.py assets/map_style/protomaps_light_de.json
"""
import json
import sys

SIMPLE_NAME = ["coalesce", ["get", "name:de"], ["get", "name"]]


def fix_in(expr):
    """Recursively rewrite modern `in`(needle, literal-haystack) syntax."""
    if not isinstance(expr, list):
        return expr
    if (
        len(expr) == 3
        and expr[0] == "in"
        and isinstance(expr[1], list)
        and len(expr[1]) == 2
        and expr[1][0] == "get"
        and isinstance(expr[2], list)
        and len(expr[2]) == 2
        and expr[2][0] == "literal"
    ):
        return ["in", expr[1][1], *expr[2][1]]
    return [fix_in(part) for part in expr]


def is_complex(expr):
    if not isinstance(expr, list) or not expr:
        return False
    # Auch tief verschachtelte format-/Mehrschrift-Konstrukte erwischen.
    return expr[0] in ("format", "case") or '"format"' in json.dumps(expr)


def main(path):
    with open(path, encoding="utf-8") as f:
        style = json.load(f)

    kept = []
    for layer in style["layers"]:
        layout = layer.get("layout", {})
        if "icon-image" in layout:
            # Icons brauchen Sprites, die wir nicht ausliefern. Ebenen mit
            # Text (Städtenamen, POIs) behalten wir ohne Icon; reine
            # Icon-Ebenen und Straßenschilder fliegen ganz raus.
            if "text-field" not in layout or layer["id"] == "roads_shields":
                continue
            for key in [k for k in layout if k.startswith("icon-")]:
                del layout[key]
            for key in [k for k in layer.get("paint", {}) if k.startswith("icon-")]:
                del layer["paint"][key]
        for section in ("paint", "layout", "filter"):
            if section == "filter":
                if "filter" in layer:
                    layer["filter"] = fix_in(layer["filter"])
                continue
            block = layer.get(section)
            if not block:
                continue
            for key, value in list(block.items()):
                block[key] = fix_in(value)
        if is_complex(layout.get("text-field")):
            layout["text-field"] = SIMPLE_NAME
        kept.append(layer)

    style["layers"] = kept
    with open(path, "w", encoding="utf-8") as f:
        json.dump(style, f, ensure_ascii=False, indent=1)
    print(f"OK: {len(kept)} Ebenen geschrieben")


if __name__ == "__main__":
    main(sys.argv[1])
