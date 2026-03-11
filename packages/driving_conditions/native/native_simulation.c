#include <math.h>
#include <stdint.h>
#include <time.h>

typedef struct {
  float overall_mean;
  float grip_mean;
  float visibility_mean;
  float fleet_mean;
  float overall_variance;
  uint32_t incident_count;
  float execution_ms;
} SimulationResponse;

static float clampf_range(float value, float min_value, float max_value) {
  if (value < min_value) {
    return min_value;
  }

  if (value > max_value) {
    return max_value;
  }

  return value;
}

static uint32_t xorshift32(uint32_t state) {
  if (state == 0u) {
    state = 2463534242u;
  }

  state ^= state << 13;
  state ^= state >> 17;
  state ^= state << 5;
  return state;
}

static float uniform01(uint32_t* state) {
  *state = xorshift32(*state);
  return (float) (*state & 0x00FFFFFFu) / 16777216.0f;
}

SimulationResponse simulation_run_batch(
  uint32_t runs,
  uint32_t seed,
  float speed,
  float grip_factor,
  uint32_t surface_code,
  float visibility_meters
) {
  const float fleet_confidence_score = 0.8f;
  const uint32_t effective_runs = runs == 0u ? 1u : runs;
  clock_t start = clock();
  float total_overall = 0.0f;
  float total_grip = 0.0f;
  float total_visibility = 0.0f;
  float total_fleet = 0.0f;
  float total_overall_squared = 0.0f;
  uint32_t incident_count = 0u;

  (void) surface_code;

  for (uint32_t run_index = 0; run_index < effective_runs; ++run_index) {
    uint32_t state = seed ^ (0x9E3779B9u + (run_index * 747796405u));
    float grip_jitter = uniform01(&state) * 0.1f;
    float visibility_jitter = uniform01(&state) * 0.1f;
    float speed_factor = clampf_range(speed / 130.0f, 0.0f, 1.0f);
    float grip_score = clampf_range(
      grip_factor * (1.0f - grip_jitter) * (1.0f - speed_factor * 0.3f),
      0.0f,
      1.0f
    );
    float visibility_norm = clampf_range(visibility_meters / 1000.0f, 0.0f, 1.0f);
    float visibility_score = clampf_range(
      visibility_norm * (1.0f - visibility_jitter),
      0.0f,
      1.0f
    );
    float overall =
      grip_score * 0.4f + visibility_score * 0.4f + fleet_confidence_score * 0.2f;

    total_overall += overall;
    total_grip += grip_score;
    total_visibility += visibility_score;
    total_fleet += fleet_confidence_score;
    total_overall_squared += overall * overall;

    if (overall < 0.4f) {
      ++incident_count;
    }
  }

  clock_t end = clock();
  float overall_mean = total_overall / (float) effective_runs;
  float variance =
    (total_overall_squared / (float) effective_runs) - (overall_mean * overall_mean);
  float execution_ms = ((float) (end - start) * 1000.0f) / (float) CLOCKS_PER_SEC;

  SimulationResponse response = {
    .overall_mean = overall_mean,
    .grip_mean = total_grip / (float) effective_runs,
    .visibility_mean = total_visibility / (float) effective_runs,
    .fleet_mean = total_fleet / (float) effective_runs,
    .overall_variance = variance,
    .incident_count = incident_count,
    .execution_ms = execution_ms,
  };

  return response;
}