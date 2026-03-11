cmake_minimum_required(VERSION 3.16)

project(simulation_engine LANGUAGES C)

add_library(simulation_engine SHARED native_simulation.c)
target_compile_features(simulation_engine PRIVATE c_std_11)

set_target_properties(simulation_engine PROPERTIES
  OUTPUT_NAME simulation_engine
)