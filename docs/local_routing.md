# Local Routing Deployment Guide

Run OSRM and Valhalla locally so SNGNav routes without any cloud dependency.
Both engines run as Docker containers on a standard Linux machine or a
Raspberry Pi 4/5.

For full device bring-up on arm64 Linux targets, pair this guide with
`docs/arm_deployment.md`.

## Prerequisites

- Docker (or Podman)
- ~2 GB disk for OSM data + container images
- For Raspberry Pi: 4 GB+ RAM recommended (8 GB for Valhalla tile build)

## 1. Download OSM Data

SNGNav defaults to the Chūbu region (central Japan — Nagoya, Shizuoka,
Nagano). Pick any Geofabrik extract for your area.

```bash
mkdir -p data/routing
cd data/routing
wget https://download.geofabrik.de/asia/japan/chubu-latest.osm.pbf
```

File size: ~250 MB (Chūbu). Smaller extracts are available per prefecture.

## 2. OSRM (Recommended for Driving)

OSRM is 95–133× faster than Valhalla for driving routes (~5 ms vs ~465 ms).
Use OSRM as the primary engine for car navigation.

### Prepare Data

```bash
docker run --rm -t -v $(pwd)/data/routing:/data \
  ghcr.io/project-osrm/osrm-backend:latest \
  osrm-extract -p /opt/car.lua /data/chubu-latest.osm.pbf

docker run --rm -t -v $(pwd)/data/routing:/data \
  ghcr.io/project-osrm/osrm-backend:latest \
  osrm-partition /data/chubu-latest.osrm

docker run --rm -t -v $(pwd)/data/routing:/data \
  ghcr.io/project-osrm/osrm-backend:latest \
  osrm-customize /data/chubu-latest.osrm
```

### Start Server

```bash
docker run -d --name osrm -p 5000:5000 \
  -v $(pwd)/data/routing:/data \
  ghcr.io/project-osrm/osrm-backend:latest \
  osrm-routed --algorithm mld /data/chubu-latest.osrm
```

### Verify

```bash
curl "http://localhost:5000/route/v1/driving/136.8815,35.1709;137.1535,34.9693?overview=full&steps=true"
```

This queries a route from Nagoya Station to Okazaki — the same corridor
SNGNav's mock route covers. You should get a JSON response with `"code": "Ok"`.

### SNGNav Configuration

```bash
flutter run -d linux \
  --dart-define=ROUTING_ENGINE=osrm
```

`OsrmRoutingEngine` defaults to `http://localhost:5000`.

## 3. Valhalla (Multi-Modal + Japanese Instructions)

Use Valhalla when you need bicycle/pedestrian routing, isochrones, or
Japanese-language turn-by-turn instructions.

### Build Tiles

```bash
docker run --rm -t -v $(pwd)/data/routing:/data \
  ghcr.io/valhalla/valhalla:latest \
  valhalla_build_tiles \
  -c /data/valhalla.json \
  /data/chubu-latest.osm.pbf
```

If no `valhalla.json` exists, Valhalla creates a default config. The tile
build takes 5–15 minutes depending on hardware (longer on Raspberry Pi).

### Start Server

```bash
docker run -d --name valhalla -p 8002:8002 \
  -v $(pwd)/data/routing:/data \
  ghcr.io/valhalla/valhalla:latest
```

### Verify

```bash
curl -X POST "http://localhost:8002/route" \
  -H "Content-Type: application/json" \
  -d '{
    "locations": [
      {"lat": 35.1709, "lon": 136.8815},
      {"lat": 34.9693, "lon": 137.1535}
    ],
    "costing": "auto",
    "language": "ja-JP"
  }'
```

### SNGNav Configuration

```bash
flutter run -d linux \
  --dart-define=ROUTING_ENGINE=valhalla
```

`ValhallaRoutingEngine` defaults to `http://localhost:8002`.

## 4. Raspberry Pi Notes

Both engines run on Raspberry Pi 4 (4 GB) and Pi 5 (8 GB).

| Engine | RPi 4 (4 GB) | RPi 5 (8 GB) |
|--------|:------------:|:------------:|
| OSRM (Chūbu) | ✓ ~180 MB RAM | ✓ ~180 MB RAM |
| Valhalla tile build | Slow (~30 min) | ✓ (~10 min) |
| Valhalla server | ✓ ~420 MB RAM | ✓ ~420 MB RAM |

For RPi 4 with 4 GB, OSRM is recommended — it uses less memory and responds
faster. Running both engines simultaneously requires ~600 MB, leaving room
for SNGNav and the OS.

Use the 64-bit Raspberry Pi OS for Docker support. Arm64 container images
are available for both OSRM and Valhalla.

## 5. Running Both Engines

SNGNav can fall back from OSRM to Valhalla automatically. To run both:

```bash
# Start OSRM on port 5000
docker run -d --name osrm -p 5000:5000 \
  -v $(pwd)/data/routing:/data \
  ghcr.io/project-osrm/osrm-backend:latest \
  osrm-routed --algorithm mld /data/chubu-latest.osrm

# Start Valhalla on port 8002
docker run -d --name valhalla -p 8002:8002 \
  -v $(pwd)/data/routing:/data \
  ghcr.io/valhalla/valhalla:latest
```

Configure SNGNav for OSRM primary with Valhalla available:

```bash
flutter run -d linux \
  --dart-define=ROUTING_ENGINE=osrm
```

The `RoutingBloc` uses whichever engine is configured. To switch engines,
change the `--dart-define` flag — no code changes required.

## Summary

| What | Command |
|------|---------|
| Download map data | `wget` from Geofabrik |
| OSRM: prepare | `osrm-extract` → `osrm-partition` → `osrm-customize` |
| OSRM: run | `docker run ... -p 5000:5000` |
| Valhalla: prepare | `valhalla_build_tiles` |
| Valhalla: run | `docker run ... -p 8002:8002` |
| SNGNav: connect | `--dart-define=ROUTING_ENGINE=osrm` or `valhalla` |

No cloud account. No API key. No subscription. Local routing on local hardware.
