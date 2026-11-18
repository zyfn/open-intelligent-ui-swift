#!/usr/bin/env python3
"""Build the SDK's offline GCJ-02 coverage resource from a pinned GeoJSON."""

import argparse
import hashlib
import json
from pathlib import Path

SOURCE_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/"
    "geojson/ne_50m_admin_0_map_units.geojson"
)
SOURCE_SHA256 = "b8d421aca6e9e08e8cdf09cc26af111cc3e0deba4fe915611d58ade71e8a4db0"
LICENSE_URL = "https://www.naturalearthdata.com/about/terms-of-use/"
# Amap documents GCJ-02 input for these map units. Keep the units distinct so
# islands and polygon holes retain the topology of the original dataset.
MAP_UNITS = {"CHN", "HKG", "MAC", "TWN"}
DEFAULT_OUTPUT = (
    Path(__file__).resolve().parents[2]
    / "Sources/SwiftOpenUI/Resources/map-coordinate-coverage.json"
)


def main() -> None:
    parser = argparse.ArgumentParser(epilog=f"Source: {SOURCE_URL}")
    parser.add_argument("source", type=Path, help="Unmodified source GeoJSON file")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    raw = args.source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise SystemExit("Source GeoJSON does not match the pinned Natural Earth file.")
    areas = []
    units = set()
    for feature in json.loads(raw)["features"]:
        unit = feature["properties"]["GU_A3"]
        if unit in MAP_UNITS:
            units.add(unit)
            geometry = feature["geometry"]
            coordinates = geometry["coordinates"]
            if geometry["type"] == "Polygon":
                areas.append(coordinates)
            elif geometry["type"] == "MultiPolygon":
                areas.extend(coordinates)
            else:
                raise SystemExit(f"Unsupported geometry for map unit {unit}.")
    if units != MAP_UNITS:
        raise SystemExit(f"Missing map units: {sorted(MAP_UNITS - units)}")

    result = {
        "source": SOURCE_URL,
        "sourceSHA256": SOURCE_SHA256,
        "license": LICENSE_URL,
        "mapUnits": sorted(units),
        "type": "MultiPolygon",
        "coordinates": areas,
    }
    args.output.write_text(json.dumps(result, separators=(",", ":")) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
