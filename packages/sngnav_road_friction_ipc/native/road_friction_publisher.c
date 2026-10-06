// A real iceoryx2 publisher for SNGNav road friction.
//
// Author: rust-systems-engineer (RSE), 2026-09-12.
// Derived from examples/c/publish_subscribe/src/publisher.c in
// eclipse-iceoryx/iceoryx2 @ 05a3a8fa59b8 (Apache-2.0 OR MIT).
// SPDX-License-Identifier: Apache-2.0
//
// Publishes a scripted series so the Dart side can be SEEN classifying real
// cross-process bytes rather than a fixture:
//
//     80 -> grip   50 -> reduced   18 -> icy   quality=0 -> unknown
//
// Those four verdict names are RoadGrip's, read from the sink this series
// exists to drive: kuksa_dart_sdk 0.2.9 RoadFriction.classify — icy below 30,
// reduced below 60, grip above, and null -> unknown. The values are chosen to
// land one in each band with margin, so a threshold that moves slightly does
// not silently turn this proof into a tautology.
//
// looping, ~200 ms apart. The fourth sample is the one that matters: it
// carries quality=0 and a deliberately ABSURD friction_percent, so a receiver
// that ignores the quality flag reports a wrong grip rather than "unknown" —
// the failure is made loud instead of plausible.

#include "iox2/iceoryx2.h"
#include "sngnav_road_friction.h"

#if defined(_WIN32) || defined(WIN32) || defined(__WIN32__) || defined(_WIN64)
#define alignof __alignof
#else
#include <stdalign.h>
#endif

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// quality == 0 means NOT MEASURED. The payload value is then meaningless by
// contract; this one is chosen so that misreading it is obvious, not subtle.
// -999.0 is outside RoadFriction's declared 0..100 range, so a receiver that
// ignored the quality flag would hit the sink's contract-violation branch
// rather than being handed a believable grip figure.
#define UNMEASURED_SENTINEL (-999.0)

struct scripted_sample {
    double  friction_percent;
    uint8_t quality;
    const char* expect;
};

static const struct scripted_sample SERIES[] = {
    { 80.0,                 1, "grip"    },
    { 50.0,                 1, "reduced" },
    { 18.0,                 1, "icy"     },
    { UNMEASURED_SENTINEL,  0, "unknown" },
};
static const size_t SERIES_LEN = sizeof(SERIES) / sizeof(SERIES[0]);

static int64_t now_unix_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) != 0) {
        return 0;
    }
    return (int64_t) ts.tv_sec * 1000000000LL + (int64_t) ts.tv_nsec;
}

int main(int argc, char** argv) {
    // 0 = forever; otherwise stop after N samples so a test can bound the run.
    uint32_t max_samples = 0;
    if (argc > 1) {
        max_samples = (uint32_t) strtoul(argv[1], NULL, 10);
    }

    iox2_set_log_level_from_env_or(iox2_log_level_e_WARN);
    int ret_val = 0;

    // Every caller-allocatable struct is passed as NULL so the library
    // heap-allocates it. This is the whole discipline: the caller never
    // declares a size for an iceoryx2 struct, so a size it got wrong cannot
    // exist. The only layout this program declares is sngnav_road_friction_t.
    iox2_node_builder_h node_builder = iox2_node_builder_new(NULL);
    iox2_node_h node = NULL;
    ret_val = iox2_node_builder_create(node_builder, NULL, iox2_service_type_e_IPC, &node);
    if (ret_val != IOX2_OK) {
        printf("publisher: could not create node, error %d\n", ret_val);
        return 1;
    }

    const char* service_name_value = SNGNAV_ROAD_FRICTION_SERVICE;
    iox2_service_name_h service_name = NULL;
    ret_val = iox2_service_name_new(NULL, service_name_value, strlen(service_name_value), &service_name);
    if (ret_val != IOX2_OK) {
        printf("publisher: could not create service name, error %d\n", ret_val);
        goto drop_node;
    }

    iox2_service_name_ptr service_name_ptr = iox2_cast_service_name_ptr(service_name);
    iox2_service_builder_h service_builder = iox2_node_service_builder(&node, NULL, service_name_ptr);
    iox2_service_builder_pub_sub_h builder_pub_sub = iox2_service_builder_pub_sub(service_builder);

    // sizeof/alignof are taken from the compiler HERE, never written as
    // literals. iceoryx2 stores these with the type name and refuses a
    // subscriber whose numbers disagree — the coarse cross-process check.
    const char* payload_type_name = SNGNAV_ROAD_FRICTION_TYPE_NAME;
    ret_val = iox2_service_builder_pub_sub_set_payload_type_details(&builder_pub_sub,
                                                                   iox2_type_variant_e_FIXED_SIZE,
                                                                   payload_type_name,
                                                                   strlen(payload_type_name),
                                                                   sizeof(sngnav_road_friction_t),
                                                                   alignof(sngnav_road_friction_t));
    if (ret_val != IOX2_OK) {
        printf("publisher: could not set payload type details, error %d\n", ret_val);
        goto drop_service_name;
    }

    iox2_port_factory_pub_sub_h service = NULL;
    ret_val = iox2_service_builder_pub_sub_open_or_create(builder_pub_sub, NULL, &service);
    if (ret_val != IOX2_OK) {
        printf("publisher: could not open or create service, error %d\n", ret_val);
        goto drop_service_name;
    }

    iox2_port_factory_publisher_builder_h publisher_builder =
        iox2_port_factory_pub_sub_publisher_builder(&service, NULL);
    iox2_publisher_h publisher = NULL;
    ret_val = iox2_port_factory_publisher_builder_create(publisher_builder, NULL, &publisher);
    if (ret_val != IOX2_OK) {
        printf("publisher: could not create publisher, error %d\n", ret_val);
        goto drop_service;
    }

    printf("publisher: service '%s' type '%s' size %zu align %zu\n",
           service_name_value,
           payload_type_name,
           sizeof(sngnav_road_friction_t),
           alignof(sngnav_road_friction_t));
    fflush(stdout);

    uint32_t sequence = 0;
    // 0 sec + 200 ms per cycle. iox2_node_wait returns non-OK when the node is
    // asked to shut down, which is how Ctrl-C ends the loop cleanly.
    while (iox2_node_wait(&node, 0, 200000000) == IOX2_OK) {
        const struct scripted_sample* s = &SERIES[sequence % SERIES_LEN];

        iox2_sample_mut_h sample = NULL;
        ret_val = iox2_publisher_loan_slice_uninit(&publisher, NULL, &sample, 1);
        if (ret_val != IOX2_OK) {
            printf("publisher: could not loan sample, error %d\n", ret_val);
            goto drop_publisher;
        }

        sngnav_road_friction_t* payload = NULL;
        iox2_sample_mut_payload_mut(&sample, (void**) &payload, NULL);

        // Written field by field, and the reserved bytes explicitly, because a
        // loaned sample is recycled shared memory and is NOT zeroed. Leaving
        // them unwritten would ship whatever the last sample left there.
        payload->friction_percent    = s->friction_percent;
        payload->measured_at_unix_ns = now_unix_ns();
        payload->sequence            = sequence;
        payload->quality             = s->quality;
        payload->reserved0           = 0;
        payload->reserved1           = 0;
        payload->reserved2           = 0;

        ret_val = iox2_sample_mut_send(sample, NULL);
        if (ret_val != IOX2_OK) {
            printf("publisher: could not send sample, error %d\n", ret_val);
            goto drop_publisher;
        }

        if (s->quality == 0) {
            printf("publisher: seq=%u quality=0 NOT MEASURED (expect %s)\n", sequence, s->expect);
        } else {
            printf("publisher: seq=%u friction=%.1f%% (expect %s)\n", sequence, s->friction_percent, s->expect);
        }
        fflush(stdout);

        sequence += 1;
        if (max_samples != 0 && sequence >= max_samples) {
            break;
        }
    }

drop_publisher:
    iox2_publisher_drop(publisher);
drop_service:
    iox2_port_factory_pub_sub_drop(service);
drop_service_name:
    iox2_service_name_drop(service_name);
drop_node:
    iox2_node_drop(node);
    return ret_val == IOX2_OK ? 0 : 1;
}
