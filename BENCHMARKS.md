# SNGNav Performance Benchmarks

Machine D reference numbers. Established Sprint 14 (March 2026).

**Machine D**: MacBook Pro 2017, i5-7267U 2C/4T 3.1 GHz, 8 GB LPDDR3, Ubuntu 24.04

Run benchmarks:

```bash
flutter test test/benchmark/performance_benchmark_test.dart --reporter expanded
```

## Kalman Filter (4D EKF)

| Operation | min | p50 | mean | p95 | p99 | max | n |
|:----------|----:|----:|-----:|----:|----:|----:|--:|
| predict(1s) | 5 µs | 15 µs | 16.0 µs | 27 µs | 52 µs | 497 µs | 1000 |
| predict(100ms) | 5 µs | 7 µs | 9.5 µs | 17 µs | 34 µs | 136 µs | 1000 |
| predict+update | 13 µs | 14 µs | 26.0 µs | 64 µs | 159 µs | 1159 µs | 1000 |
| KalmanFilter() | 10 µs | 16 µs | 17.8 µs | 26 µs | 55 µs | 411 µs | 1000 |
| KalmanFilter.withState() | 9 µs | 13 µs | 15.9 µs | 26 µs | 50 µs | 778 µs | 1000 |

**Tunnel scenario (60s GPS loss)**: 301 µs total (5.0 µs/step). Accuracy: 229.0 m. Safety cap not exceeded.

**Tunnel + recovery (30s + GPS)**: 156 µs total. Post-recovery accuracy: 23.1 m.

**Convergence profile (60 GPS fixes, 1 Hz)**:

| Fix # | Accuracy |
|------:|---------:|
| 1 | 6.46 m |
| 10 | 3.38 m |
| 30 | 3.40 m |
| 60 | 3.40 m |

Total: 942 µs (15.7 µs/update). Converges by fix 10.

## Polyline Decoding

Measured through `calculateRoute()` with mock HTTP (includes JSON parse + decode).

### Polyline5 (OSRM, precision 1e5)

| Points | min | p50 | mean | p95 | max | n |
|-------:|----:|----:|-----:|----:|----:|--:|
| 10 | 347 µs | 444 µs | 491 µs | 799 µs | 1182 µs | 200 |
| 100 | 332 µs | 389 µs | 422 µs | 595 µs | 1012 µs | 200 |
| 500 | 363 µs | 466 µs | 503 µs | 708 µs | 1137 µs | 200 |
| 2000 | 357 µs | 398 µs | 439 µs | 642 µs | 913 µs | 200 |

### Polyline6 (Valhalla, precision 1e6)

| Points | min | p50 | mean | p95 | max | n |
|-------:|----:|----:|-----:|----:|----:|--:|
| 10 | 309 µs | 336 µs | 391 µs | 601 µs | 1222 µs | 200 |
| 100 | 286 µs | 343 µs | 391 µs | 571 µs | 934 µs | 200 |
| 500 | 301 µs | 341 µs | 433 µs | 788 µs | 2632 µs | 200 |
| 2000 | 396 µs | 425 µs | 468 µs | 690 µs | 849 µs | 200 |

**Observation**: Polyline decoding is not the bottleneck. Both engines decode 2000 points in < 1 ms (p95). The JSON parse + mock HTTP overhead dominates at all sizes.

## Route Response Parsing (Full Pipeline)

| Engine | Maneuvers | Points | min | p50 | mean | p95 | max |
|:-------|----------:|-------:|----:|----:|-----:|----:|----:|
| OSRM | 25 | 500 | 344 µs | 439 µs | 485 µs | 762 µs | 1503 µs |
| Valhalla | 25 | 500 | 314 µs | 372 µs | 435 µs | 669 µs | 1437 µs |

Both engines parse a realistic 25-maneuver/500-point response in < 1 ms (p95). Sub-frame latency (<16.6 ms) is confirmed for the parse path.

## Live Network Latency (Sprint 15, March 5 2026)

Route: Sakae Station → Higashiokazaki Station (~50 km). Machine D (Japan).

| Engine | Server | Location | Mean (5x warm) | Response size |
|:-------|:-------|:---------|---------------:|--------------:|
| OSRM | `router.project-osrm.org` | Zürich, CH | 1,717 ms | 43,645 bytes |
| Valhalla | `valhalla1.openstreetmap.de` | Falkenstein, DE | 1,367 ms | 14,527 bytes |

**Correction**: Sprint 14 reported "OSRM 4.9 ms, Valhalla 464 ms" — those figures were not reproducible. Live measurements show both engines at ~1.3–1.7 seconds from Japan. The latency is dominated by geographic distance (Japan → Europe, ~300 ms one-way RTT). Valhalla is slightly faster (20% lower mean) with a 3x smaller response.

**Latency decomposition** (Valhalla, typical warm request ~1.3s):

| Component | Time | % |
|:----------|-----:|--:|
| Network RTT (Japan → Germany × 2) | ~600 ms | 46% |
| TLS overhead | ~300 ms | 23% |
| Server-side routing | ~300 ms | 23% |
| Transfer (14 KB) | ~100 ms | 8% |

For sub-frame latency (<16.6 ms), local Valhalla deployment is required.

## App Startup & Runtime (Sprint 15, March 5 2026)

Build: release, snow_scene entrypoint. Machine D.

| Metric | Value |
|:-------|------:|
| Cold start (to RSS >100 MB) | 309 ms |
| Steady-state RSS | 193 MB |
| Idle CPU (simulation mode, 1 Hz GPS) | ~16% |
| Bundle size | 51 MB (42 MB Flutter engine, 5.1 MB app, 1.8 MB SQLite) |
| Threads | 26–32 |

Idle CPU is driven by `SimulatedLocationProvider` (1 Hz) → 6 nested BlocBuilder rebuilds → FlutterMap re-render. Expected to drop to ~3% on Machine E (12C/16T).

## Dead Reckoning Activation Latency

| Mode | GPS Timeout | DR Positions (500ms window) | DR Active |
|:-----|:------------|----------------------------:|:---------:|
| Kalman | 200 ms | 4 | Yes |
| Linear | 200 ms | 4 | Yes |

Both modes activate DR after the GPS timeout fires and begin emitting extrapolated positions at the configured extrapolation interval (100 ms). The activation latency is bounded by `gpsTimeout` — no additional startup cost.

## Key Findings

1. **Kalman filter is cheap**: 15 µs per predict step. A 60-second tunnel costs 301 µs total. Well within the 16.6 ms frame budget.
2. **Convergence is fast**: The filter converges to ~3.4 m accuracy within 10 GPS fixes (10 seconds at 1 Hz).
3. **Polyline decoding is not a bottleneck**: All sizes decode in < 1 ms. Network I/O dominates route latency.
4. **Parse times are engine-agnostic**: OSRM and Valhalla parse at equivalent speed (~400 µs).
5. **DR activation is deterministic**: Bounded by `gpsTimeout` parameter. No warm-up cost.
6. **No engine performance gap** (Sprint 15): Both OSRM and Valhalla demo servers respond in ~1.3–1.7s from Japan. Latency is geographic (Europe servers), not engine-specific. Valhalla is 20% faster with 3x smaller responses. Local deployment needed for sub-frame routing.
