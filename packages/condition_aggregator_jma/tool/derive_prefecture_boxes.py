#!/usr/bin/env python3
"""Derive JMA prefecture-office bounding boxes BY MEASUREMENT from Geofabrik
`.osm.pbf` extracts, and join them to JMA's own office master.

    python3 tool/derive_prefecture_boxes.py \
        --pbf ../../tohoku-260701.osm.pbf \
        --pbf ../../kanto-latest.osm.pbf \
        --pbf ../../chubu-latest.osm.pbf \
        --offices test/fixtures/jma_area_offices.frozen_2026-08-24.json \
        --out test/fixtures/jma_prefecture_boxes.derived.json

WHY THIS EXISTS
---------------
Through 0.7.0 `kJmaPrefectureBoundingBoxes` held 13 of JMA's 58 offices. The
45 absent ones resolve to `[]` in `prefectureCodesForPoint`, so a driver
standing in them is not read at all.

The eight-Hokkaido-office correction that preceded this was derived by
MEASURING against JMA's frozen area master rather than from recall, and that
is what caught `'010000'` -- a code JMA does not have, which every point in
the snowiest prefecture in Japan resolved to. That master carries only
`{name, parent}`. It has NO GEOMETRY. So the boxes cannot come from it, and
they must not come from anyone's memory: a bounding box written from recall
decides whether HER prefecture is read at all, and is a Promise-1 violation.

They come from the only geometry actually on this disk: the OSM extracts.

THE JOIN IS MECHANICAL, NOT HAND-MADE
-------------------------------------
For 46 of JMA's 58 offices the office name in JMA's own master IS the
prefecture name (`宮城県`, `長野県`, ...). Those join to an OSM
`admin_level=4 boundary=administrative` relation on an exact `name` match.

The 12 that do not join are not failures and are not forced:

  * 8 Hokkaido offices (`宗谷地方` ...) are SUB-prefectural -- Hokkaido is one
    `admin_level=4` relation containing all eight. They are already
    catalogued from the earlier measured correction and are left untouched.
  * `奄美地方` / `鹿児島県（奄美地方除く）` split Kagoshima, and the four
    Okinawa offices split Okinawa. Neither split is an `admin_level=4`
    boundary, and neither prefecture is in these extracts anyway.

An office that does not join is REPORTED AS UNCOVERED. It is never guessed.

TRUNCATION IS THE REAL HAZARD, AND IT IS TESTED FOR
---------------------------------------------------
A Geofabrik extract clips at its own region border. A prefecture straddling
that border can appear with SOME of its member ways present, yielding a box
that is silently TOO SMALL -- the exact failure mode that loses a driver.

So a relation is accepted only when every one of these holds:

  * every member way of the relation was found in the extract;
  * every node referenced by those ways was found in the extract;
  * the resulting box does not touch the extract's own declared header bbox
    (within `EDGE_EPSILON_DEG`).

Anything else is emitted with `complete: false` and an explicit reason, and
is NOT eligible for the catalogue. A prefecture present in more than one
extract is resolved to the complete reading; if two complete readings
disagree beyond `AGREEMENT_EPSILON_DEG` that is an error, not an average.

Data (c) OpenStreetMap contributors, ODbL 1.0.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from osm_pbf_min import (  # noqa: E402
    Pbf,
    block_granularity,
    block_groups,
    decode_packed_varints,
    iter_fields,
    string_table,
    zigzag,
)

# A box within this distance of the extract's own header bbox is treated as
# possibly clipped by the extract boundary rather than by geography.
EDGE_EPSILON_DEG = 0.02

# Two independent extracts measuring the same prefecture must agree to this.
AGREEMENT_EPSILON_DEG = 0.001

# Boxes are stored at this precision. 4dp ~ 11 m at these latitudes: far
# finer than the prefecture-level segmentation of the JMA feed, and it keeps
# the generated Dart readable.
BOX_DECIMALS = 4


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 22), b""):
            digest.update(chunk)
    return digest.hexdigest()


def classify(pbf: Pbf) -> dict[int, set[int]]:
    """Map blob index -> set of PrimitiveGroup field numbers it contains."""
    kinds: dict[int, set[int]] = {}
    with open(pbf.path, "rb") as handle:
        for index, (offset, size, _) in enumerate(pbf.blobs):
            handle.seek(offset)
            block = Pbf._inflate(handle.read(size))
            found: set[int] = set()
            for begin, end in block_groups(block):
                for field, _wire, _value in iter_fields(block, begin, end):
                    found.add(field)
            kinds[index] = found
    return kinds


# --- pass 1: admin_level=4 boundary relations -------------------------------


def read_admin4_relations(
    pbf: Pbf, kinds: dict[int, set[int]]
) -> dict[str, dict]:
    """name -> {'id': relation id, 'ways': [way ids], 'name_en': str|None}."""
    out: dict[str, dict] = {}
    with open(pbf.path, "rb") as handle:
        for index, (offset, size, _) in enumerate(pbf.blobs):
            if 4 not in kinds[index]:
                continue
            handle.seek(offset)
            block = Pbf._inflate(handle.read(size))
            strings = string_table(block)
            for gbegin, gend in block_groups(block):
                for field, wire, value in iter_fields(block, gbegin, gend):
                    if field != 4 or wire != 2:
                        continue
                    parsed = _parse_relation(block, value, strings)
                    if parsed is None:
                        continue
                    name, record = parsed
                    # A name appearing twice at admin_level=4 is ambiguous;
                    # keep both so the caller can refuse rather than pick.
                    out.setdefault(name, record)
                    if out[name]["id"] != record["id"]:
                        out[name].setdefault("duplicates", []).append(
                            record["id"]
                        )
    return out


def _parse_relation(block: bytes, span, strings: list[bytes]):
    begin, end = span
    rel_id = None
    keys = vals = memids = types = None
    for field, wire, value in iter_fields(block, begin, end):
        if field == 1 and wire == 0:
            rel_id = value
        elif field == 2 and wire == 2:
            keys = decode_packed_varints(block, value[0], value[1])
        elif field == 3 and wire == 2:
            vals = decode_packed_varints(block, value[0], value[1])
        elif field == 9 and wire == 2:
            memids = np.cumsum(
                zigzag(decode_packed_varints(block, value[0], value[1]))
            )
        elif field == 10 and wire == 2:
            types = decode_packed_varints(block, value[0], value[1])
    if rel_id is None or keys is None or vals is None:
        return None
    tags = {
        strings[int(k)].decode("utf-8"): strings[int(v)].decode("utf-8")
        for k, v in zip(keys, vals)
    }
    if tags.get("boundary") != "administrative":
        return None
    if tags.get("admin_level") != "4":
        return None
    name = tags.get("name")
    if not name:
        return None
    if memids is None or types is None:
        return None
    ways = [int(m) for m, t in zip(memids, types) if int(t) == 1]
    if not ways:
        return None
    return name, {
        "id": rel_id,
        "ways": ways,
        "name_en": tags.get("name:en"),
    }


# --- pass 2: node refs of the member ways -----------------------------------


def read_way_refs(
    pbf: Pbf, kinds: dict[int, set[int]], wanted: set[int]
) -> dict[int, list[int]]:
    found: dict[int, list[int]] = {}
    with open(pbf.path, "rb") as handle:
        for index, (offset, size, _) in enumerate(pbf.blobs):
            if 3 not in kinds[index]:
                continue
            handle.seek(offset)
            block = Pbf._inflate(handle.read(size))
            for gbegin, gend in block_groups(block):
                for field, wire, value in iter_fields(block, gbegin, gend):
                    if field != 3 or wire != 2:
                        continue
                    way_id = None
                    refs = None
                    for wfield, wwire, wvalue in iter_fields(
                        block, value[0], value[1]
                    ):
                        if wfield == 1 and wwire == 0:
                            way_id = wvalue
                            if way_id not in wanted:
                                break        # id is first: skip the rest
                        elif wfield == 8 and wwire == 2:
                            refs = np.cumsum(
                                zigzag(
                                    decode_packed_varints(
                                        block, wvalue[0], wvalue[1]
                                    )
                                )
                            )
                    if way_id in wanted and refs is not None:
                        found[way_id] = [int(r) for r in refs]
    return found


# --- pass 3: coordinates of the referenced nodes ----------------------------


def read_node_coords(
    pbf: Pbf, kinds: dict[int, set[int]], wanted: set[int]
) -> dict[int, tuple[float, float]]:
    coords: dict[int, tuple[float, float]] = {}
    remaining = set(wanted)
    with open(pbf.path, "rb") as handle:
        for index, (offset, size, _) in enumerate(pbf.blobs):
            if 2 not in kinds[index] or not remaining:
                continue
            handle.seek(offset)
            block = Pbf._inflate(handle.read(size))
            granularity, lat_offset, lon_offset = block_granularity(block)
            for gbegin, gend in block_groups(block):
                for field, wire, value in iter_fields(block, gbegin, gend):
                    if field != 2 or wire != 2:
                        continue
                    _dense(
                        block, value, granularity, lat_offset, lon_offset,
                        remaining, coords,
                    )
    return coords


def _dense(block, span, granularity, lat_offset, lon_offset, remaining,
           coords) -> None:
    ids = lats = lons = None
    for field, wire, value in iter_fields(block, span[0], span[1]):
        if wire != 2:
            continue
        if field == 1:
            ids = np.cumsum(
                zigzag(decode_packed_varints(block, value[0], value[1]))
            )
        elif field == 8:
            lats = np.cumsum(
                zigzag(decode_packed_varints(block, value[0], value[1]))
            )
        elif field == 9:
            lons = np.cumsum(
                zigzag(decode_packed_varints(block, value[0], value[1]))
            )
    if ids is None or lats is None or lons is None:
        return
    # Cheap reject: this block's id range cannot hold anything we want.
    hits = [i for i, node_id in enumerate(ids.tolist()) if node_id in remaining]
    if not hits:
        return
    for i in hits:
        node_id = int(ids[i])
        latitude = 1e-9 * (lat_offset + granularity * int(lats[i]))
        longitude = 1e-9 * (lon_offset + granularity * int(lons[i]))
        coords[node_id] = (latitude, longitude)
        remaining.discard(node_id)


# --- per-extract derivation --------------------------------------------------


def _round(value: float) -> float:
    return round(value, BOX_DECIMALS)


def derive_from_extract(path: str, office_names: set[str]) -> dict:
    """Measure every admin_level=4 relation in ONE extract whose `name` is one
    of `office_names`.

    Returns ``{'meta': {...}, 'readings': {name: reading}}`` where a reading
    always carries ``complete`` and, when False, ``reason``. Nothing here
    guesses: an incomplete reading is reported, never repaired.
    """
    started = time.time()
    pbf = Pbf(path)
    kinds = classify(pbf)

    relations = read_admin4_relations(pbf, kinds)
    wanted = {
        name: record
        for name, record in relations.items()
        if name in office_names
    }

    way_ids: set[int] = set()
    for record in wanted.values():
        way_ids.update(record["ways"])
    way_refs = read_way_refs(pbf, kinds, way_ids)

    node_ids: set[int] = set()
    for refs in way_refs.values():
        node_ids.update(refs)
    coords = read_node_coords(pbf, kinds, node_ids)

    header = pbf.header_bbox or {}
    readings: dict[str, dict] = {}

    for name, record in sorted(wanted.items()):
        reading: dict = {
            "relation_id": record["id"],
            "name_en": record.get("name_en"),
            "member_ways": len(record["ways"]),
        }
        if "duplicates" in record:
            reading.update(
                complete=False,
                reason=(
                    f"{1 + len(record['duplicates'])} distinct admin_level=4 "
                    f"relations carry the name {name!r} in this extract "
                    f"(ids {[record['id']] + record['duplicates']}); the "
                    "reader refuses to pick one"
                ),
            )
            readings[name] = reading
            continue

        missing_ways = [w for w in record["ways"] if w not in way_refs]
        if missing_ways:
            reading.update(
                complete=False,
                reason=(
                    f"{len(missing_ways)} of {len(record['ways'])} member ways "
                    "are absent from this extract -- the relation is clipped "
                    "by the extract border, so the box would be TOO SMALL"
                ),
            )
            readings[name] = reading
            continue

        points: list[tuple[float, float]] = []
        missing_nodes = 0
        for way in record["ways"]:
            for ref in way_refs[way]:
                found = coords.get(ref)
                if found is None:
                    missing_nodes += 1
                else:
                    points.append(found)
        if missing_nodes:
            reading.update(
                complete=False,
                reason=(
                    f"{missing_nodes} node(s) referenced by the member ways "
                    "are absent from this extract -- the outline is torn, so "
                    "the box would be TOO SMALL"
                ),
            )
            readings[name] = reading
            continue
        if not points:
            reading.update(
                complete=False, reason="relation resolved to zero coordinates"
            )
            readings[name] = reading
            continue

        south = min(p[0] for p in points)
        north = max(p[0] for p in points)
        west = min(p[1] for p in points)
        east = max(p[1] for p in points)
        reading.update(
            south=_round(south),
            west=_round(west),
            north=_round(north),
            east=_round(east),
            nodes=len(points),
        )

        touching = [
            edge
            for edge, value, limit in (
                ("south", south, header.get("south")),
                ("north", north, header.get("north")),
                ("west", west, header.get("west")),
                ("east", east, header.get("east")),
            )
            if limit is not None and abs(value - limit) <= EDGE_EPSILON_DEG
        ]
        if touching:
            reading.update(
                complete=False,
                reason=(
                    "the derived box touches the extract's own header bbox on "
                    f"{'/'.join(touching)} (within {EDGE_EPSILON_DEG} deg) -- "
                    "this is the extract border, not geography"
                ),
            )
        else:
            reading["complete"] = True
        readings[name] = reading

    return {
        "meta": {
            "path": os.path.abspath(path),
            "basename": os.path.basename(path),
            "bytes": os.path.getsize(path),
            "sha256": sha256_of(path),
            "mtime_utc": dt.datetime.fromtimestamp(
                os.path.getmtime(path), dt.timezone.utc
            ).strftime("%Y-%m-%d"),
            "header_bbox": header,
            "admin4_relations_seen": len(relations),
            "office_names_matched": len(wanted),
            "seconds": round(time.time() - started, 1),
        },
        "readings": readings,
    }


# --- reconciliation across extracts + join to JMA's office master ------------


def reconcile(per_extract: list[dict]) -> tuple[dict, dict]:
    """Fold per-extract readings into one measurement per prefecture name.

    A name measured COMPLETE in more than one extract must agree to within
    `AGREEMENT_EPSILON_DEG` on every edge. Disagreement is an error, never an
    average -- two independent measurements of one boundary that differ mean
    one of them is wrong, and averaging would bury which.
    """
    accepted: dict[str, dict] = {}
    rejected: dict[str, list[dict]] = {}

    for extract in per_extract:
        basename = extract["meta"]["basename"]
        derived_on = extract["meta"]["mtime_utc"]
        for name, reading in extract["readings"].items():
            if not reading.get("complete"):
                rejected.setdefault(name, []).append(
                    {"extract": basename, "reason": reading.get("reason")}
                )
                continue
            candidate = {
                "south": reading["south"],
                "west": reading["west"],
                "north": reading["north"],
                "east": reading["east"],
                "name_en": reading.get("name_en"),
                "relation_id": reading["relation_id"],
                "member_ways": reading["member_ways"],
                "nodes": reading["nodes"],
                "source_extract": basename,
                "derived_from_extract_dated": derived_on,
            }
            if name not in accepted:
                accepted[name] = candidate
                continue
            standing = accepted[name]
            drift = {
                edge: round(abs(standing[edge] - candidate[edge]), 6)
                for edge in ("south", "west", "north", "east")
                if abs(standing[edge] - candidate[edge])
                > AGREEMENT_EPSILON_DEG
            }
            if drift:
                raise SystemExit(
                    f"DISAGREEMENT: {name} measured complete in both "
                    f"{standing['source_extract']} and {basename}, but the "
                    f"edges differ beyond {AGREEMENT_EPSILON_DEG} deg: {drift}."
                    " This is not averaged -- one reading is wrong and the "
                    "cause must be found before any box is shipped."
                )
            standing.setdefault("corroborated_by", []).append(basename)

    return accepted, rejected


def join_to_offices(
    offices: dict[str, dict], accepted: dict[str, dict]
) -> tuple[dict, dict]:
    """JMA office code -> measured box, by EXACT office-name match.

    An office whose name is not an `admin_level=4` relation name we measured
    is returned as uncovered WITH ITS REASON. It is never approximated.
    """
    boxes: dict[str, dict] = {}
    uncovered: dict[str, dict] = {}
    for code, office in sorted(offices.items()):
        name = office["name"]
        if name in accepted:
            boxes[code] = dict(accepted[name], name=name)
        else:
            uncovered[code] = {"name": name}
    return boxes, uncovered


# --- emit --------------------------------------------------------------------


def dart_rows(boxes: dict[str, dict]) -> str:
    lines: list[str] = []
    for code, box in sorted(boxes.items()):
        label = box.get("name_en") or box["name"]
        lines.append(
            f"      // {box['name']} ({label}) -- measured from "
            f"{box['source_extract']} ({box['derived_from_extract_dated']}), "
            f"OSM relation {box['relation_id']}"
        )
        lines.append(
            f"      '{code}': (south: {box['south']:.4f}, "
            f"west: {box['west']:.4f}, north: {box['north']:.4f}, "
            f"east: {box['east']:.4f}),"
        )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Derive JMA prefecture-office bounding boxes BY MEASUREMENT from "
            "Geofabrik .osm.pbf extracts, joined to JMA's own office master."
        )
    )
    parser.add_argument(
        "--pbf", action="append", required=True, metavar="PATH",
        help="an .osm.pbf extract to measure (repeatable)",
    )
    parser.add_argument("--offices", required=True, metavar="PATH")
    parser.add_argument("--out", required=True, metavar="PATH")
    parser.add_argument("--dart-out", metavar="PATH")
    args = parser.parse_args(argv)

    with open(args.offices, encoding="utf-8") as handle:
        master = json.load(handle)
    offices = master["offices"]
    office_names = {office["name"] for office in offices.values()}

    per_extract: list[dict] = []
    for path in args.pbf:
        print(f"measuring {path} ...", file=sys.stderr, flush=True)
        extract = derive_from_extract(path, office_names)
        meta = extract["meta"]
        complete = sum(
            1 for r in extract["readings"].values() if r.get("complete")
        )
        print(
            f"  {meta['admin4_relations_seen']} admin_level=4 relations, "
            f"{meta['office_names_matched']} match an office name, "
            f"{complete} COMPLETE  [{meta['seconds']}s]",
            file=sys.stderr, flush=True,
        )
        per_extract.append(extract)

    accepted, rejected = reconcile(per_extract)
    boxes, uncovered = join_to_offices(offices, accepted)

    document = {
        "_provenance": {
            "generated_utc": dt.datetime.now(dt.timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            ),
            "generator": "tool/derive_prefecture_boxes.py",
            "attribution": "Data (c) OpenStreetMap contributors, ODbL 1.0",
            "method": (
                "admin_level=4 boundary=administrative relation, exact "
                "office-name match against JMA's frozen area master; a "
                "reading is accepted only when every member way and every "
                "referenced node is present in the extract AND the box does "
                "not touch the extract's own header bbox"
            ),
            "offices_master": {
                "path": args.offices,
                "sha256": sha256_of(args.offices),
                "offices": len(offices),
            },
            "extracts": [e["meta"] for e in per_extract],
            "edge_epsilon_deg": EDGE_EPSILON_DEG,
            "agreement_epsilon_deg": AGREEMENT_EPSILON_DEG,
            "box_decimals": BOX_DECIMALS,
        },
        "boxes": boxes,
        "uncovered": uncovered,
        "rejected_readings": rejected,
    }

    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(document, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")

    if args.dart_out:
        with open(args.dart_out, "w", encoding="utf-8") as handle:
            handle.write(dart_rows(boxes) + "\n")

    print(
        f"\n{len(boxes)} of {len(offices)} offices MEASURED; "
        f"{len(uncovered)} uncovered by these extracts.",
        file=sys.stderr,
    )
    for code, box in sorted(boxes.items()):
        print(
            f"  {code} {box['name']:<10} "
            f"S{box['south']:.4f} W{box['west']:.4f} "
            f"N{box['north']:.4f} E{box['east']:.4f}  "
            f"<- {box['source_extract']}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
