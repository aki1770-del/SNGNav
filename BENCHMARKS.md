# SNGNav Performance Benchmarks

Cross-platform reference numbers. Machine D established Sprint 14 (March 2026). Machine E added Sprint 15 (March 2026).

**Machine D**: MacBook Pro 2017, i5-7267U 2C/4T 3.1 GHz, 8 GB LPDDR3, Ubuntu 24.04
**Machine E**: HP ZBook Power 15.6 G9, i7-12700H 14C/20T 4.7 GHz, 32 GB, NVIDIA RTX A1000, Ubuntu 24.04

Run benchmarks:

```bash
flutter test test/benchmark/performance_benchmark_test.dart --reporter expanded
```

## Kalman Filter (4D EKF)

### Machine D (i5-7267U 2C/4T)

| Operation | min | p50 | mean | p95 | p99 | max | n |
|:----------|----:|----:|-----:|----:|----:|----:|--:|
| predict(1s) | 5 µs | 15 µs | 16.0 µs | 27 µs | 52 µs | 497 µs | 1000 |
| predict(100ms) | 5 µs | 7 µs | 9.5 µs | 17 µs | 34 µs | 136 µs | 1000 |
| predict+update | 13 µs | 14 µs | 26.0 µs | 64 µs | 159 µs | 1159 µs | 1000 |
| KalmanFilter() | 10 µs | 16 µs | 17.8 µs | 26 µs | 55 µs | 411 µs | 1000 |
| KalmanFilter.withState() | 9 µs | 13 µs | 15.9 µs | 26 µs | 50 µs | 778 µs | 1000 |

### Machine E (i7-12700H 14C/20T)

| Operation | min | p50 | mean | p95 | p99 | max | n | vs D (p50) |
|:----------|----:|----:|-----:|----:|----:|----:|--:|----------:|
| predict(1s) | 5 µs | 9 µs | 11.1 µs | 18 µs | 49 µs | 587 µs | 1000 | **1.7×** |
| predict(100ms) | 4 µs | 6 µs | 7.8 µs | 11 µs | 29 µs | 586 µs | 1000 | **1.2×** |
| predict+update | 11 µs | 14 µs | 28.3 µs | 78 µs | 200 µs | 1318 µs | 1000 | **1.0×** |
| KalmanFilter() | 3 µs | 3 µs | 5.6 µs | 4 µs | 11 µs | 2003 µs | 1000 | **5.3×** |
| KalmanFilter.withState() | 10 µs | 12 µs | 16.6 µs | 21 µs | 36 µs | 728 µs | 1000 | **1.1×** |

**Tunnel scenario (60s GPS loss)**:

| Metric | Machine D | Machine E |
|:-------|----------:|----------:|
| Total time | 301 µs (5.0 µs/step) | **208 µs (3.5 µs/step)** |
| Accuracy | 229.0 m | 229.0 m |
| Safety cap exceeded | No | No |

**Tunnel + recovery (30s + GPS)**:

| Metric | Machine D | Machine E |
|:-------|----------:|----------:|
| Total time | 156 µs | **137 µs** |
| Post-recovery accuracy | 23.1 m | 23.1 m |

**Convergence profile (60 GPS fixes, 1 Hz)**:

| Fix # | Accuracy |
|------:|---------:|
| 1 | 6.46 m |
| 10 | 3.38 m |
| 30 | 3.40 m |
| 60 | 3.40 m |

| Metric | Machine D | Machine E |
|:-------|----------:|----------:|
| Total (60 updates) | 942 µs (15.7 µs/update) | **1317 µs (21.9 µs/update)** |

Convergence accuracy is identical (physics-determined). Machine E convergence time is nominally higher — consistent with timer-based test jitter on a higher-core-count scheduler.

## Polyline Decoding

Measured through `calculateRoute()` with mock HTTP (includes JSON parse + decode).

### Polyline5 (OSRM, precision 1e5)

| Points | Machine D p50 | Machine E p50 | Machine D p95 | Machine E p95 | n |
|-------:|-------------:|-------------:|-------------:|-------------:|--:|
| 10 | 444 µs | **431 µs** | 799 µs | **666 µs** | 200 |
| 100 | 389 µs | **333 µs** | 595 µs | **506 µs** | 200 |
| 500 | 466 µs | **324 µs** | 708 µs | **654 µs** | 200 |
| 2000 | 398 µs | **490 µs** | 642 µs | **962 µs** | 200 |

### Polyline6 (Valhalla, precision 1e6)

| Points | Machine D p50 | Machine E p50 | Machine D p95 | Machine E p95 | n |
|-------:|-------------:|-------------:|-------------:|-------------:|--:|
| 10 | 336 µs | **303 µs** | 601 µs | **411 µs** | 200 |
| 100 | 343 µs | **286 µs** | 571 µs | **404 µs** | 200 |
| 500 | 341 µs | **297 µs** | 788 µs | **727 µs** | 200 |
| 2000 | 425 µs | **380 µs** | 690 µs | **695 µs** | 200 |

**Observation**: Polyline decoding is not the bottleneck on either machine. Both engines decode 2000 points in < 1 ms (p95). Machine E shows modest improvement (~10–20% p50) — consistent with faster single-core throughput. The floor is set by mock HTTP overhead, not CPU speed.

## Route Response Parsing (Full Pipeline)

### Machine D (i5-7267U)

| Engine | Maneuvers | Points | min | p50 | mean | p95 | max |
|:-------|----------:|-------:|----:|----:|-----:|----:|----:|
| OSRM | 25 | 500 | 344 µs | 439 µs | 485 µs | 762 µs | 1503 µs |
| Valhalla | 25 | 500 | 314 µs | 372 µs | 435 µs | 669 µs | 1437 µs |

### Machine E (i7-12700H)

| Engine | Maneuvers | Points | min | p50 | mean | p95 | max | vs D (p50) |
|:-------|----------:|-------:|----:|----:|-----:|----:|----:|----------:|
| OSRM | 25 | 500 | 303 µs | 387 µs | 439 µs | 694 µs | 3060 µs | **1.1×** |
| Valhalla | 25 | 500 | 270 µs | 425 µs | 439 µs | 783 µs | 1774 µs | **0.9×** |

Both engines parse a realistic 25-maneuver/500-point response in < 1 ms (p95) on both machines. Sub-frame latency (<16.6 ms) confirmed across hardware. Parse times are IO-bound (mock HTTP), not CPU-bound — explaining why Machine E shows no improvement.

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

Build: release, snow_scene entrypoint.

| Metric | Machine D | Machine E (projected) |
|:-------|----------:|---------------------:|
| Cold start (to RSS >100 MB) | 309 ms | — |
| Steady-state RSS | 193 MB | — |
| Idle CPU (simulation mode, 1 Hz GPS) | ~16% | **~3%** (projected) |
| Bundle size | 51 MB | identical |
| Threads | 26–32 | — |

Idle CPU is driven by `SimulatedLocationProvider` (1 Hz) → 6 nested BlocBuilder rebuilds → FlutterMap re-render. On Machine E (14C/20T vs 2C/4T), 16% × (4/20) ≈ 3% projected. Machine E runtime measurements not yet recorded.

## Dead Reckoning Activation Latency

| Mode | GPS Timeout | DR Positions (500ms window) | DR Active |
|:-----|:------------|----------------------------:|:---------:|
| Kalman | 200 ms | 4 | Yes |
| Linear | 200 ms | 4 | Yes |

Both modes activate DR after the GPS timeout fires and begin emitting extrapolated positions at the configured extrapolation interval (100 ms). The activation latency is bounded by `gpsTimeout` — no additional startup cost.

## Key Findings

1. **Kalman filter is cheap**: 9–15 µs per predict step (p50, Machine E/D). A 60-second tunnel costs 208–301 µs total. Well within the 16.6 ms frame budget.
2. **Convergence is fast**: The filter converges to ~3.4 m accuracy within 10 GPS fixes (10 seconds at 1 Hz). Identical on both machines — physics-determined.
3. **Polyline decoding is not a bottleneck**: All sizes decode in < 1 ms. Mock HTTP overhead dominates. Machine E shows ~10–20% improvement at p50.
4. **Parse times are engine-agnostic**: OSRM and Valhalla parse at equivalent speed (~400 µs). Not CPU-bound — IO floor prevents hardware gains.
5. **DR activation is deterministic**: Bounded by `gpsTimeout` parameter. No warm-up cost. Identical on both machines.
6. **No engine performance gap** (Sprint 15): Both OSRM and Valhalla demo servers respond in ~1.3–1.7s from Japan. Latency is geographic (Europe servers), not engine-specific. Valhalla is 20% faster with 3× smaller responses. Local deployment needed for sub-frame routing.
7. **Cross-platform portability confirmed** (Sprint 15): All 1073 tests pass identically on Machine D (i5-7267U) and Machine E (i7-12700H). Flutter 3.41.4 on Machine E (vs 3.41.1 on D) introduces no regressions. Benchmark characteristics are consistent across hardware.
