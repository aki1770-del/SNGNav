/* SNGNav road-friction wire struct — the ONE place a layout is declared twice.
 *
 * Author: rust-systems-engineer (RSE), 2026-09-12.
 * SPDX-License-Identifier: Apache-2.0
 *
 * THIS FILE IS WHERE THE SCAR IS.
 * ------------------------------------------------------------------
 * A Dart-declared layout meeting a C-declared layout is the exact shape that,
 * in this codebase, returned 0.312216 on a 0-1 safety scale instead of
 * crashing: a plausible number, no error, no log line. The stale-size probe in
 * this seat's scratch showed IOX2_OK returned with 88 bytes clobbered. Nothing
 * about a wrong layout announces itself.
 *
 * Three properties keep it small, and each is deliberate:
 *
 *  1. NO ALIGNMENT ATTRIBUTES. `__attribute__((aligned(n)))` is silently
 *     dropped by ffigen — measured 2026-09-12: 2 of 60 struct sizes wrong, no
 *     `@ffi.Align` anywhere in 25,581 generated lines, no warning. A layout
 *     with nothing to drop cannot be silently mis-dropped.
 *
 *  2. FLAT SCALARS ONLY, and that is why `reserved` is three named bytes
 *     rather than `uint8_t reserved[3]`. CHANGED FROM THE SEAM, DECLARED
 *     LOUDLY: driving_conditions/tool/abi_layout_check.dart REFUSES any C
 *     field containing '[' (it throws Unverifiable and exits 2), so the array
 *     form would have made the mandated layout check unable to run at all —
 *     a guard that exits "could not verify" on the one struct it exists for.
 *     The wire is UNCHANGED. Measured on x86_64 with gcc -O2:
 *         uint8_t reserved[3]      -> size=24 align=8, fields at 0/8/16/20/21
 *         three named uint8_t      -> size=24 align=8, fields at 0/8/16/20/21,22,23
 *     Byte-identical. The bytes a publisher writes are the same bytes.
 *
 *  3. NO VERSION SYMBOL EXISTS IN THE LIBRARY THIS TRAVELS OVER. Measured on
 *     the built libiceoryx2_ffi_c.so: zero exported symbols matching
 *     version/abi/revision/semver across 660 iox2_* symbols. A stale iceoryx2
 *     is undetectable at open. iceoryx2 does check a payload type name and
 *     size at service-open, which catches a WIDTH change — it does not catch a
 *     field reorder at constant width. That is what the layout check is for.
 */
#ifndef SNGNAV_ROAD_FRICTION_H
#define SNGNAV_ROAD_FRICTION_H

#include <stdint.h>

typedef struct {
    /* VSS convention: PERCENT, 0-100 — NOT a 0.0-1.0 ratio. Measured
     * 2026-08-26: VSS friction is percent, and reading it as a ratio is a
     * 100x error that still looks like a number. IGNORED when quality == 0. */
    double   friction_percent;
    int64_t  measured_at_unix_ns;
    uint32_t sequence;
    /* 0 = NOT MEASURED, 1 = measured. Absence never rides the measurement
     * scale: there is no friction value that means "we do not know". */
    uint8_t  quality;
    uint8_t  reserved0;
    uint8_t  reserved1;
    uint8_t  reserved2;
} sngnav_road_friction_t;

/* The iceoryx2 service both ends open. A mismatch here is a silent no-data
 * condition, not an error, so it is declared once and shared. */
#define SNGNAV_ROAD_FRICTION_SERVICE "sngnav/road_friction"

/* iceoryx2 records a payload type name alongside size and alignment at
 * service-open and refuses a mismatch. That refusal is the only cross-process
 * layout check that exists here, and it is a coarse one — it compares a name,
 * a size and an alignment, never a field order. */
#define SNGNAV_ROAD_FRICTION_TYPE_NAME "sngnav_road_friction_t"

#endif /* SNGNAV_ROAD_FRICTION_H */
