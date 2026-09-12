# Build the SNGNav road-friction iceoryx2 publisher.
#
# Author: rust-systems-engineer (RSE), 2026-09-12.
#
# Depends on ../tool/build_iceoryx2.sh having produced libiceoryx2_ffi_c.so and
# the cbindgen header. This Makefile does NOT rebuild iceoryx2 — it reads that
# script's own output, so the header and the library it links against always
# come from the same pinned build. A Makefile that located them independently
# could pair a new header with an old library, which is the defect class this
# package exists to avoid.
#
#   make            build ./road_friction_publisher
#   make run        run it forever (Ctrl-C to stop)
#   make clean

# The include of the generated env file makes make restart, and the restart
# would otherwise pick the env file as the default goal.
.DEFAULT_GOAL := road_friction_publisher

CC      ?= cc
# _POSIX_C_SOURCE: -std=c11 alone hides clock_gettime/CLOCK_REALTIME, which are
# POSIX, not ISO C. Asking for the POSIX feature set explicitly is more honest
# than switching to -std=gnu11 and inheriting every GNU extension by accident.
CFLAGS  ?= -O2 -Wall -Wextra -Werror -std=c11 -D_POSIX_C_SOURCE=200809L
BUILD_SCRIPT := $(CURDIR)/../tool/build_iceoryx2.sh

# One invocation, cached in a file: the script is idempotent but not free.
ICEORYX2_ENV := $(CURDIR)/.iceoryx2.env

$(ICEORYX2_ENV):
	@echo "[native] resolving iceoryx2 build via $(BUILD_SCRIPT)"
	@bash $(BUILD_SCRIPT) > $@.tmp && mv $@.tmp $@

-include $(ICEORYX2_ENV)

road_friction_publisher: road_friction_publisher.c sngnav_road_friction.h $(ICEORYX2_ENV)
	$(CC) $(CFLAGS) -I$(ICEORYX2_INCLUDE_DIR) -I$(CURDIR) \
	    -o $@ road_friction_publisher.c \
	    $(ICEORYX2_LIB) -Wl,-rpath,$(dir $(ICEORYX2_LIB)) -lpthread -ldl -lm

.PHONY: run clean env
run: road_friction_publisher
	./road_friction_publisher

env: $(ICEORYX2_ENV)
	@cat $(ICEORYX2_ENV)

clean:
	rm -f road_friction_publisher $(ICEORYX2_ENV) $(ICEORYX2_ENV).tmp
