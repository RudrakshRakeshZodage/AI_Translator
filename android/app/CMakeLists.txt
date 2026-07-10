cmake_minimum_required(VERSION 3.10.2)

project(native_bridge VERSION 1.0.0 LANGUAGES CXX)

add_library(native_bridge SHARED
    ../../src/native_bridge.cpp
)

# In a real setup, you would add llama.cpp and whisper.cpp source files here
# or link to their pre-compiled libraries.
# Add Whisper.cpp Subdirectory
# Disable tests and examples in whisper.cpp to speed up compilation
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "")
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "")
set(WHISPER_NO_AVX ON CACHE BOOL "")
set(WHISPER_NO_AVX2 ON CACHE BOOL "")
set(WHISPER_NO_FMA ON CACHE BOOL "")
set(WHISPER_NO_F16C ON CACHE BOOL "")
# Force stability flags into the cache so the sub-projects can't override them
set(GGML_NO_NEON OFF CACHE BOOL "Enable NEON" FORCE)
set(GGML_NO_ACCELERATE ON CACHE BOOL "Force disable Accelerate" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "Force disable OpenMP" FORCE)

add_definitions(-DGGML_USE_CPU=1 -DGGML_NO_ACCELERATE=1 -DGGML_NO_OPENMP=1)
add_subdirectory(../../src/whisper whisper_build)

target_link_libraries(native_bridge whisper log)

target_include_directories(native_bridge PUBLIC
    ../../src
    ../../src/whisper/include
)
