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

Beyond the renderer fixes it makes one deliberate design change:
hiking paths, forest tracks and trails get their own visible layers
instead of disappearing into the `roads_other` catch-all — see
`emphasize_paths`.

Usage (after regenerating the style with @protomaps/basemaps):
    python3 tool/transform_map_style.py assets/map_style/protomaps_light_de.json
"""
import json
import sys

SIMPLE_NAME = ["coalesce", ["get", "name:de"], ["get", "name"]]

# Die Wanderwege-Töne stehen bewusst HIER und nicht in
# `lib/core/app_colors.dart`: Diesen Stil erzeugt ein Werkzeug, das kein
# Dart liest. Ockerbraun, weil es sich sowohl vom Erdton (#e2dfda) als
# auch vom Grün der landcover-Ebene absetzt.
PATH_TRACK_COLOR = "#9a6b3f"
PATH_COLOR = "#a9793f"

# Wegarten, die keine Wanderwege sind: Bürgersteige und Fußgängerüberwege
# hängen an jeder Stadtstraße. Sie fallen damit ganz weg — für eine
# Pilz-App ist das Gewinn, nicht Verlust.
URBAN_PATH_DETAILS = ("sidewalk", "crossing")


def path_layers():
    """Die zwei Wanderwege-Ebenen — bei jedem Aufruf gleich aufgebaut.

    Eigene Funktion, damit [emphasize_paths] sie ERSETZEN statt ergänzen
    kann: Nur so bleibt [transform] ein Fixpunkt.
    """
    common = [["!has", "is_tunnel"], ["!has", "is_bridge"], ["==", "kind", "path"]]
    return [
        {
            "id": "roads_path_track",
            "type": "line",
            "source": "protomaps",
            "source-layer": "roads",
            "filter": ["all"] + common + [["==", "kind_detail", "track"]],
            "paint": {
                "line-color": PATH_TRACK_COLOR,
                "line-dasharray": [4, 1.5],
                "line-width": [
                    "interpolate", ["exponential", 1.6], ["zoom"],
                    12, 0.9, 15, 2, 20, 7,
                ],
            },
        },
        {
            "id": "roads_path",
            "type": "line",
            "source": "protomaps",
            "source-layer": "roads",
            "filter": ["all"] + common
            + [["!=", "kind_detail", "track"], ["!=", "kind_detail", "pier"]]
            + [["!=", "kind_detail", detail] for detail in URBAN_PATH_DETAILS],
            "paint": {
                "line-color": PATH_COLOR,
                "line-dasharray": [2, 1.5],
                "line-width": [
                    "interpolate", ["exponential", 1.6], ["zoom"],
                    12, 0.7, 15, 1.5, 20, 5,
                ],
            },
        },
    ]


def emphasize_paths(style):
    """Wanderwege bekommen eine eigene Ebene statt der Sammelgrube.

    **Das Problem:** Protomaps steckt Pfade, Forstwege, Steige und
    Reitwege als `kind == "path"` in dieselbe Ebene wie Zufahrten und
    Bahnsteige (`kind == "other"`). Der LIGHT-Flavor malt die Ebene
    `#ebebeb` auf einen `#e2dfda`-Boden und bei z14 mit 0,5 px — für
    eine Pilz-App ist damit ausgerechnet das unsichtbar, worauf man
    läuft. Kein Datenproblem: Die Wege stehen vollständig in den
    Kacheln.

    **Nachgemessen** (2026-08-20, Archiv `de_saarland` aus den
    Nomad-Releases, Kacheln z12–z14 über Range-Requests): Forstwege
    (`kind_detail == "track"`) liegen ab z12 in den Kacheln, alles
    Übrige (`path`, `footway`, `cycleway`, `steps`) ab z13. Die
    Breiten beginnen deshalb bei z12 statt wie bisher bei z14.

    **Idempotent, und das ist Pflicht:** `tool/generated_assets.py`
    wendet [transform] auf das committete Asset an und verlangt
    byteidentische Ausgabe. Deshalb stellt dieser Schritt einen
    Endzustand her — alte Ebenen gleicher id raus, frische rein — statt
    etwas anzuhängen.
    """
    layers = style["layers"]
    if not any(layer["id"] == "roads_other" for layer in layers):
        raise SystemExit("roads_other fehlt — der erzeugte Stil sieht anders aus als erwartet")
    fresh = path_layers()
    ours = {layer["id"] for layer in fresh}
    layers = [layer for layer in layers if layer["id"] not in ours]
    at = next(i for i, layer in enumerate(layers) if layer["id"] == "roads_other")
    # Die Sammelgrube behält nur noch, was wirklich Nebensache ist.
    layers[at]["filter"] = [
        "all",
        ["!has", "is_tunnel"],
        ["!has", "is_bridge"],
        ["==", "kind", "other"],
        ["!=", "kind_detail", "pier"],
    ]
    # Hinter roads_other, also UNTER den Straßen — eine Straße, die einen
    # Forstweg kreuzt, gehört obenauf.
    layers[at + 1:at + 1] = fresh
    style["layers"] = layers
    return style


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


def transform(style):
    """Der Umbau selbst — mutiert [style] und gibt ihn zurück.

    Von [main] getrennt, damit `tool/generated_assets.py` ihn AUF das
    committete Asset anwenden und prüfen kann, dass nichts passiert.
    Genau dieser Fixpunkt ist die Aussage: Wer den Stil neu generiert
    und diesen Schritt vergisst, hat wieder graue Landflächen ohne
    Beschriftung — und zwar lautlos, denn der Renderer lässt die
    Ebenen, die er nicht versteht, einfach weg.
    """
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
    return emphasize_paths(style)


def render(style):
    """Die EINE Schreibweise des Assets.

    Eigene Funktion, weil die Fixpunkt-Prüfung Byte für Byte vergleicht:
    Stünde die Formatierung an zwei Stellen, wiche sie beim ersten
    Eingriff ab, und die Prüfung meldete einen Unterschied, den es
    inhaltlich nicht gibt.
    """
    return json.dumps(style, ensure_ascii=False, indent=1)


def main(path):
    with open(path, encoding="utf-8") as f:
        style = json.load(f)
    style = transform(style)
    with open(path, "w", encoding="utf-8") as f:
        f.write(render(style))
    print(f"OK: {len(style['layers'])} Ebenen geschrieben")


if __name__ == "__main__":
    main(sys.argv[1])
