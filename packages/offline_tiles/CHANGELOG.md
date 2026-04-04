# Changelog

## 0.4.0

- Migrate to `mbtiles ^0.5.0` and `sqlite3 ^3.2.0` (native assets).
- Remove EOL `sqflite` dependency.
- Remove unused `flutter_map_mbtiles` phantom dependency.
- Internal API update: `MbTiles(path:)`, `MbTiles.create(path:)`, `close()` replacing `dispose()`.
- Public API unchanged: `OfflineTileManager(mbtilesPath:)` contract preserved.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

