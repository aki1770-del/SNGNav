"""Minimal, dependency-light OSM PBF reader (protobuf wire format by hand).

WHY THIS EXISTS INSTEAD OF `osmium`
-----------------------------------
`sngnav-app/tool/extract_akita_boundary.py` (masterplan repo) already reads
`admin_level=4` areas from a Geofabrik `.osm.pbf` via `osmium.SimpleHandler`.
That is the same mechanism and it is deliberately NOT reinvented here.

It is not *usable* here, for two measured reasons (both re-measured 2026-08-26):

  1. `python3 -c "import osmium"` -> ModuleNotFoundError, in the system
     interpreter AND in the masterplan `.venv`; `osmium`/`osmconvert`/
     `osmfilter`/`ogr2ogr` are all absent from PATH. The sibling tool cannot
     run on this machine today.
  2. It resolves ONE hard-coded prefecture name into polygon RINGS for tile
     clipping. This module needs EVERY `admin_level=4` name in an extract,
     reduced to a bounding box, plus a mechanical completeness verdict per
     relation. Rings are the wrong output and one name is the wrong scope.

So the mechanism is re-used, the tool is not. Only `numpy` + the stdlib
`zlib` are required -- both measured present.

WHAT IT DOES NOT DO
-------------------
This is not a general OSM library. It decodes exactly the fields needed to
turn `admin_level=4` boundary relations into bounding boxes: relation
tags/members, way node refs, and node coordinates. It ignores metadata,
changesets, roles, and every optional feature except `DenseNodes` (asserted
present in the header, never assumed).

Data (c) OpenStreetMap contributors, ODbL 1.0.
"""

from __future__ import annotations

import struct
import zlib

import numpy as np

# --- protobuf wire-format primitives ---------------------------------------


def read_varint(buf: bytes, i: int) -> tuple[int, int]:
    result = 0
    shift = 0
    while True:
        byte = buf[i]
        i += 1
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return result, i
        shift += 7


def iter_fields(buf: bytes, start: int = 0, end: int | None = None):
    """Yield (field_number, wire_type, value) over one protobuf message.

    For wire type 2 the value is a ``(begin, end)`` slice of ``buf``; for
    wire type 0 it is the integer. Wire types 1 and 5 are skipped with a
    ``None`` value (this format never needs a fixed64/fixed32 payload).
    """
    i = start
    end = len(buf) if end is None else end
    while i < end:
        key, i = read_varint(buf, i)
        field, wire = key >> 3, key & 7
        if wire == 0:
            value, i = read_varint(buf, i)
            yield field, wire, value
        elif wire == 2:
            length, i = read_varint(buf, i)
            yield field, wire, (i, i + length)
            i += length
        elif wire == 5:
            yield field, wire, None
            i += 4
        elif wire == 1:
            yield field, wire, None
            i += 8
        else:
            raise ValueError(f"unsupported protobuf wire type {wire}")


# --- packed-varint decoding (numpy fast path) ------------------------------


def decode_packed_varints(buf: bytes, begin: int, end: int) -> np.ndarray:
    """Decode a packed varint field into an int64 array.

    Vectorised: a varint's bytes are the run ending at the first byte whose
    continuation bit is clear, so element boundaries fall out of a single
    ``flatnonzero`` and the payload is a shifted ``add.reduceat``.
    """
    if end <= begin:
        return np.zeros(0, dtype=np.int64)
    raw = np.frombuffer(buf, dtype=np.uint8, count=end - begin, offset=begin)
    terminal = np.flatnonzero((raw & 0x80) == 0)
    if terminal.size == 0:
        raise ValueError("packed varint field ends mid-value")
    if terminal[-1] != raw.size - 1:
        raise ValueError("trailing bytes after last packed varint")
    starts = np.empty(terminal.size, dtype=np.int64)
    starts[0] = 0
    starts[1:] = terminal[:-1] + 1
    widths = terminal - starts + 1
    if widths.max() > 10:
        raise ValueError("varint wider than 10 bytes")
    # Byte position within its own varint -> shift amount.
    shift = (np.arange(raw.size, dtype=np.int64)
             - np.repeat(starts, widths)) * 7
    payload = (raw & 0x7F).astype(np.uint64) << shift.astype(np.uint64)
    return np.add.reduceat(payload, starts).astype(np.int64)


def zigzag(values: np.ndarray) -> np.ndarray:
    """Decode protobuf sint64 zigzag encoding."""
    u = values.astype(np.uint64)
    return ((u >> np.uint64(1)).astype(np.int64)
            ^ -(values & 1).astype(np.int64))


# --- blob layer -------------------------------------------------------------


class Pbf:
    """Random-access blob index over one ``.osm.pbf`` file."""

    def __init__(self, path: str):
        self.path = path
        self.blobs: list[tuple[int, int, str]] = []  # (offset, size, type)
        self.header_bbox: dict[str, float] | None = None
        self._index()

    def _index(self) -> None:
        with open(self.path, "rb") as handle:
            while True:
                length_bytes = handle.read(4)
                if len(length_bytes) < 4:
                    return
                (header_len,) = struct.unpack(">I", length_bytes)
                header = handle.read(header_len)
                blob_type = None
                data_size = None
                for field, wire, value in iter_fields(header):
                    if field == 1 and wire == 2:
                        blob_type = header[value[0]:value[1]].decode()
                    elif field == 3 and wire == 0:
                        data_size = value
                if blob_type is None or data_size is None:
                    raise ValueError("malformed BlobHeader")
                offset = handle.tell()
                if blob_type == "OSMHeader":
                    self._read_header(self._inflate(handle.read(data_size)))
                else:
                    handle.seek(data_size, 1)
                    self.blobs.append((offset, data_size, blob_type))

    @staticmethod
    def _inflate(blob: bytes) -> bytes:
        for field, wire, value in iter_fields(blob):
            if field == 1 and wire == 2:      # raw
                return blob[value[0]:value[1]]
            if field == 3 and wire == 2:      # zlib_data
                return zlib.decompress(blob[value[0]:value[1]])
        raise ValueError("blob uses an unsupported compression")

    def _read_header(self, block: bytes) -> None:
        features: list[str] = []
        for field, wire, value in iter_fields(block):
            if field == 4 and wire == 2:
                features.append(block[value[0]:value[1]].decode())
            elif field == 1 and wire == 2:
                box: dict[int, int] = {}
                for sub, subwire, subvalue in iter_fields(
                    block, value[0], value[1]
                ):
                    if subwire == 0:
                        box[sub] = subvalue
                if {1, 2, 3, 4} <= box.keys():
                    def deg(raw: int) -> float:
                        signed = (raw >> 1) ^ -(raw & 1)   # sint64 zigzag
                        return signed * 1e-9
                    self.header_bbox = {
                        "west": deg(box[1]), "east": deg(box[2]),
                        "north": deg(box[3]), "south": deg(box[4]),
                    }
        if "DenseNodes" not in features:
            raise ValueError(
                f"{self.path}: header does not declare DenseNodes; this "
                "reader decodes only DenseNodes blocks"
            )

    def block(self, offset: int, size: int) -> bytes:
        with open(self.path, "rb") as handle:
            handle.seek(offset)
            return self._inflate(handle.read(size))


def block_groups(block: bytes):
    """Yield ``(begin, end)`` slices of each PrimitiveGroup in a block."""
    for field, wire, value in iter_fields(block):
        if field == 2 and wire == 2:
            yield value


def block_granularity(block: bytes) -> tuple[int, int, int]:
    granularity, lat_offset, lon_offset = 100, 0, 0
    for field, wire, value in iter_fields(block):
        if wire != 0:
            continue
        if field == 17:
            granularity = value
        elif field == 19:
            lat_offset = value
        elif field == 20:
            lon_offset = value
    return granularity, lat_offset, lon_offset


def string_table(block: bytes) -> list[bytes]:
    for field, wire, value in iter_fields(block):
        if field == 1 and wire == 2:
            return [
                block[s:e]
                for sub, subwire, (s, e) in iter_fields(
                    block, value[0], value[1]
                )
                if sub == 1 and subwire == 2
            ]
    return []
