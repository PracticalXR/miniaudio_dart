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

# Sources (auto-refresh on new files)
file(GLOB CONFIGURE_DEPENDS MAIN_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/*/src/*.c"
)

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
    MINIAUDIO_IMPLEMENTATION
    MA_ENABLE_ONLY_SPECIFIC_BACKENDS
    MA_DEBUG_OUTPUT
)

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
        -O2
        -flto
        -fno-rtti
    )
    target_link_options(${TARGET_BASENAME} PRIVATE
        -O2
        -flto
        -sEXPORTED_FUNCTIONS=_malloc,_free
        -sEXPORTED_RUNTIME_METHODS=ccall
        -sALLOW_MEMORY_GROWTH
        -sMAXIMUM_MEMORY=1gb
        -sNO_DEFAULT_TO_CXX
        -sNO_TEXTDECODER
        -sFORCE_FILESYSTEM=1
        -sNO_FETCH_SUPPORT_INDEXEDDB
        -sAUDIO_WORKLET=1
        -sWASM_WORKERS=1
        -sASYNCIFY
        -sSTACK_SIZE=1mb
        -sSTACK_OVERFLOW_CHECK
    )

    # Copy JS loader assets to web output
    file(GLOB JS_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/js/*.js")
    add_custom_target(${TARGET_BASENAME}_assets ALL
        COMMAND ${CMAKE_COMMAND} -E make_directory "${WEB_OUTPUT_DIR}"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${JS_SOURCES} "${WEB_OUTPUT_DIR}"
        DEPENDS ${JS_SOURCES}
        COMMENT "Copying JS loader assets to ${WEB_OUTPUT_DIR}"
    )
    add_dependencies(${TARGET_BASENAME} ${TARGET_BASENAME}_assets)

    # If you have a modify_js.cmake.in, keep using it without root lookup
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/modify_js.cmake.in")
        configure_file(
            "${CMAKE_CURRENT_SOURCE_DIR}/modify_js.cmake.in"
            "${CMAKE_CURRENT_BINARY_DIR}/modify_js.cmake"
            @ONLY
        )
        add_custom_command(
            TARGET ${TARGET_BASENAME} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E echo "Modifying ${TARGET_BASENAME}.js to use locateFile"
            COMMAND ${CMAKE_COMMAND} -P "${CMAKE_CURRENT_BINARY_DIR}/modify_js.cmake"
            WORKING_DIRECTORY "${WEB_OUTPUT_DIR}"
            COMMENT "Post-processing ${TARGET_BASENAME}.js"
        )
    endif()
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
