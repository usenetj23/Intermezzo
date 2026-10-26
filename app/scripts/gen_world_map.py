#!/usr/bin/env python3
"""Builds Support/worldmap/worldmap.bin, the offline map of the location picker.

Data: Natural Earth (https://www.naturalearthdata.com, public domain), read from the nvkelso/natural-earth-vector
GeoJSON mirror: 50m land and 50m land boundary lines. Cities: GeoNames cities5000 (https://www.geonames.org, CC BY 4.0,
the attribution is shown in the picker and in Support/worldmap/README.md). Coastline rings (holes included, the app
fills them with the even-odd rule) and borders are simplified; cities of at least MIN_POPULATION people are kept. All is
written in the format described in Sources/IntermezzoKit/WorldMap.swift, cities biggest first.

Run from app/:  python3 scripts/gen_world_map.py   (needs internet; the app itself never does)
Standard library only.
"""
import io
import json
import struct
import sys
import urllib.request
import zipfile
from pathlib import Path

BASE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/"
LAND, BORDERS = "ne_50m_land", "ne_50m_admin_0_boundary_lines_land"
CITIES_URL = "https://download.geonames.org/export/dump/cities5000.zip"
TOLERANCE = 0.02          # degrees, about 2 km
MIN_POPULATION = 5_000
UNIT = 10_000             # file coordinates are Int32 in 1e-4 degrees
OUT = Path(__file__).resolve().parent.parent / "Support" / "worldmap" / "worldmap.bin"


def fetch(name):
    with urllib.request.urlopen(BASE + name + ".geojson", timeout=120) as response:
        return json.load(response)["features"]


def geonames_cities():
    """(population, lon, lat, name) from the GeoNames dump: tab separated, name in column 1, lat/lon 4/5, population 14."""
    with urllib.request.urlopen(CITIES_URL, timeout=300) as response:
        archive = zipfile.ZipFile(io.BytesIO(response.read()))
    with archive.open("cities5000.txt") as handle:
        for line in io.TextIOWrapper(handle, encoding="utf-8"):
            columns = line.rstrip("\n").split("\t")
            if len(columns) < 15 or not columns[14].isdigit():
                continue
            population = int(columns[14])
            if population >= MIN_POPULATION:
                yield population, float(columns[5]), float(columns[4]), columns[1]


def simplify(points, tolerance):
    """Douglas-Peucker without recursion; points are (lon, lat)."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        (x1, y1), (x2, y2) = points[first], points[last]
        dx, dy = x2 - x1, y2 - y1
        length = (dx * dx + dy * dy) ** 0.5
        far, index = 0.0, -1
        for i in range(first + 1, last):
            x, y = points[i]
            d = abs(dy * (x - x1) - dx * (y - y1)) / length if length else ((x - x1) ** 2 + (y - y1) ** 2) ** 0.5
            if d > far:
                far, index = d, i
        if far > tolerance:
            keep[index] = True
            stack += [(first, index), (index, last)]
    return [p for p, k in zip(points, keep) if k]


def rings(geometry):
    kind, coords = geometry["type"], geometry["coordinates"]
    if kind == "Polygon":
        return list(coords)
    if kind == "MultiPolygon":
        return [ring for polygon in coords for ring in polygon]
    if kind == "LineString":
        return [coords]
    if kind == "MultiLineString":
        return list(coords)
    return []


def paths(features, minimum_points):
    result = []
    for feature in features:
        for ring in rings(feature["geometry"]):
            line = simplify([(p[0], p[1]) for p in ring], TOLERANCE)
            if len(line) >= minimum_points:
                result.append(line)
    return result


def pack_point(lon, lat):
    return struct.pack("<ii", round(lat * UNIT), round(lon * UNIT))


def main():
    land = paths(fetch(LAND), 3)
    borders = paths(fetch(BORDERS), 2)
    cities = []
    for population, lon, lat, name in geonames_cities():
        while len(name.encode("utf-8")) > 255:
            name = name[:-1]
        cities.append((population, lon, lat, name))
    cities.sort(reverse=True)

    out = bytearray(b"WMAP" + bytes([1]))
    out += struct.pack("<II", len(land), len(borders))
    for line in land + borders:
        out += struct.pack("<I", len(line))
        for lon, lat in line:
            out += pack_point(lon, lat)
    out += struct.pack("<I", len(cities))
    for population, lon, lat, name in cities:
        encoded = name.encode("utf-8")
        out += pack_point(lon, lat) + struct.pack("<IB", population, len(encoded)) + encoded
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(out)
    print(f"{OUT}: {len(out) / 1024:.0f} KB, land {len(land)}, borders {len(borders)}, cities {len(cities)}")


if __name__ == "__main__":
    sys.exit(main())
