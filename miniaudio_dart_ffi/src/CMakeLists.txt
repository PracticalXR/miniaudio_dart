# Setup
cmake_minimum_required(VERSION 3.15)
project(miniaudio_dart_ffi VERSION 1.0.0 LANGUAGES C)

# Options and output configuration
set(WEB_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/web" CACHE PATH "Directory for web artifacts (when building with Emscripten)")

# Target names
if(NOT EMSCRIPTEN)
    set(TARGET_BASENAME miniaudio_dart_ffi)
else()
    set(TARGET_BASENAME miniaudio_dart_web)
endif()

# Ensure opus.cmake is processed BEFORE source list if you want HAVE_OPUS value early
include(cmake/opus.cmake)

set(MAIN_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/src/circular_buffer.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/engine.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/generator.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/record.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/silence_data_source.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/sound.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/stream_player.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/miniaudio/src/miniaudio.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/codec_packet_queue.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/codec_runtime.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/codec_pcm.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/crosscoder.c"
    $<$<BOOL:${HAVE_OPUS}>:${CMAKE_CURRENT_SOURCE_DIR}/src/codec_opus.c>
)

list(LENGTH MAIN_SOURCES _src_count)
if(_src_count EQUAL 0)
    message(FATAL_ERROR "No sources found; expected sources under ${CMAKE_CURRENT_SOURCE_DIR}/src and external/miniaudio/src")
endif()

# Target
if(NOT EMSCRIPTEN)
    add_library(${TARGET_BASENAME} SHARED ${MAIN_SOURCES})
else()
    add_executable(${TARGET_BASENAME} ${MAIN_SOURCES})
endif()

# Includes
target_include_directories(${TARGET_BASENAME} PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/miniaudio/include"
)

# Definitions
target_compile_definitions(${TARGET_BASENAME} PUBLIC
    DART_SHARED_LIB
    MILO_DEFAULT_LVL=MILO_LVL_NONE
    MA_ENABLE_ONLY_SPECIFIC_BACKENDS
    MA_DEBUG_OUTPUT
)
# Note: Do NOT set MINIAUDIO_IMPLEMENTATION globally; it is provided by miniaudio.c

# Platform backends
if(WIN32)
    target_compile_definitions(${TARGET_BASENAME} PUBLIC MA_ENABLE_WASAPI)
elseif(ANDROID)
    target_compile_definitions(${TARGET_BASENAME} PUBLIC MA_ENABLE_OPENSL)
elseif(EMSCRIPTEN)
    target_compile_definitions(${TARGET_BASENAME} PUBLIC
        MA_ENABLE_WEBAUDIO
        MA_ENABLE_AUDIO_WORKLETS
    )
elseif(APPLE)
    target_compile_definitions(${TARGET_BASENAME} PUBLIC MA_ENABLE_COREAUDIO)
elseif(UNIX)
    target_compile_definitions(${TARGET_BASENAME} PUBLIC
        MA_ENABLE_PULSEAUDIO
        MA_ENABLE_JACK
        MA_ENABLE_ALSA
    )
else()
    message(FATAL_ERROR "No miniaudio backend specified for the platform.")
endif()

# Properties
if(NOT EMSCRIPTEN)
    set_target_properties(${TARGET_BASENAME} PROPERTIES
        PUBLIC_HEADER "include/miniaudio_dart.h"
        OUTPUT_NAME "${TARGET_BASENAME}"
    )
else()
    # Emscripten output
    set_target_properties(${TARGET_BASENAME} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${WEB_OUTPUT_DIR}"
        OUTPUT_NAME "${TARGET_BASENAME}"
    )
    target_compile_options(${TARGET_BASENAME} PRIVATE
        -O3
        -flto
        -fno-rtti
    )
    target_link_options(${TARGET_BASENAME} PRIVATE
        -O3
        -flto
        -sEXPORTED_RUNTIME_METHODS=['ccall','cwrap','HEAPU8','HEAPF32','HEAPF64','HEAP32']
        # Export your C entry points (leading underscores)
        -sEXPORTED_FUNCTIONS=['_malloc','_free']
        -sALLOW_MEMORY_GROWTH
        -sINITIAL_MEMORY=64MB
        -sMAXIMUM_MEMORY=1GB
        -sSTACK_SIZE=16MB
        -sAUDIO_WORKLET=1
        -sWASM_WORKERS=1
        -sASYNCIFY
        -DMA_ENABLE_AUDIO_WORKLETS
    )

    # Copy assets only; drop JS patching (no external .aw.js/.ww.js emitted with =1)
    file(GLOB JS_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/js/*.js")
    add_custom_target(${TARGET_BASENAME}_assets ALL
        COMMAND ${CMAKE_COMMAND} -E make_directory "${WEB_OUTPUT_DIR}"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${JS_SOURCES} "${WEB_OUTPUT_DIR}"
        COMMENT "Copying runtime JS assets (loader, etc.)"
    )
    add_dependencies(${TARGET_BASENAME} ${TARGET_BASENAME}_assets)

    # Remove the modify_js step entirely
    # if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/modify_js.cmake.in")
    # endif()

    # >>> Copy Emscripten outputs into Dart web package after build <<<
    # Destination inside the Dart web package:
    set(DART_WEB_BUILD_DIR
        "${CMAKE_CURRENT_SOURCE_DIR}/../../miniaudio_dart_web/lib/build"
        CACHE PATH "Directory in Dart web package to receive Emscripten outputs")

    add_custom_command(TARGET ${TARGET_BASENAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${DART_WEB_BUILD_DIR}"
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${WEB_OUTPUT_DIR}" "${DART_WEB_BUILD_DIR}"
        COMMENT "Copying Emscripten outputs from ${WEB_OUTPUT_DIR} to ${DART_WEB_BUILD_DIR}"
    )
endif()

# Additional libs
if(ANDROID)
    target_link_libraries(${TARGET_BASENAME} PRIVATE OpenSLES log)
endif()

# Install (native only; optional)
if(NOT EMSCRIPTEN)
    install(TARGETS ${TARGET_BASENAME}
        RUNTIME DESTINATION bin
        LIBRARY DESTINATION lib
        ARCHIVE DESTINATION lib
        PUBLIC_HEADER DESTINATION include
    )
endif()

# Link opus to whichever target name we created
if(HAVE_OPUS)
    target_link_libraries(${TARGET_BASENAME} PRIVATE opus::opus)
    target_compile_definitions(${TARGET_BASENAME} PRIVATE HAVE_OPUS=1)

    # Pull interface include dirs.
    get_target_property(_OPUS_IFACE_INC opus::opus INTERFACE_INCLUDE_DIRECTORIES)
    if(_OPUS_IFACE_INC)
        target_include_directories(${TARGET_BASENAME} PRIVATE ${_OPUS_IFACE_INC})
    endif()

    if(DEFINED OPUS_INCLUDE_DIR AND EXISTS "${OPUS_INCLUDE_DIR}")
        target_include_directories(${TARGET_BASENAME} PRIVATE "${OPUS_INCLUDE_DIR}")
    endif()

    # Validate header layout (nested vs flat).
    set(_OPUS_HEADER_NESTED "${OPUS_INCLUDE_DIR}/opus/opus.h")
    set(_OPUS_HEADER_FLAT   "${OPUS_INCLUDE_DIR}/opus.h")
    if(EXISTS "${_OPUS_HEADER_NESTED}")
        message(STATUS "Opus header (nested): ${_OPUS_HEADER_NESTED}")
    elseif(EXISTS "${_OPUS_HEADER_FLAT}")
        message(WARNING "Opus header appears flat at ${_OPUS_HEADER_FLAT}; defining OPUS_HEADER_FLAT")
        target_compile_definitions(${TARGET_BASENAME} PRIVATE OPUS_HEADER_FLAT=1)
        # Ensure flat include dir is present.
        target_include_directories(${TARGET_BASENAME} PRIVATE "${OPUS_INCLUDE_DIR}")
    else()
        message(FATAL_ERROR "Cannot locate opus header under ${OPUS_INCLUDE_DIR}")
    endif()
else()
    message(STATUS "HAVE_OPUS=0 (Opus disabled or not found)")
endif()
