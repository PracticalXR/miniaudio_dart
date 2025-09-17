#ifndef RECORD_H
#define RECORD_H

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "../external/miniaudio/include/miniaudio.h"
#include "circular_buffer.h"
#include "export.h"

/* Forward declare InlineEncoder to avoid including codec_inline_encoder.h here. */
typedef struct InlineEncoder InlineEncoder;

typedef struct {
    char        name[256];
    ma_device_id id;
    ma_bool32   isDefault;
} CaptureDeviceInfo;

typedef struct Recorder {
    ma_encoder encoder;
    ma_encoder_config encoder_config;
    ma_device device;
    ma_device_config device_config;
    char *filename;
    bool is_recording;
    bool is_file_recording;

    CircularBuffer circular_buffer; // legacy path (file recording)

    ma_pcm_rb rb;        // streaming ring buffer
    ma_uint32 frameSize; // bytes per frame

    int sample_rate;
    int channels;
    ma_format format;

    uint8_t *encode_buffer;
    size_t encode_buffer_size;
    size_t encode_buffer_used;

    void *user_data;

    /* NEW: capture enumeration context & cache */
    ma_context context;
    bool context_initialized;
    CaptureDeviceInfo* captureInfos;
    ma_uint32 captureCount;
    ma_uint32 captureGeneration;

    InlineEncoder* inlineEncoder; /* NULL if encoder disabled */
} Recorder;

// Success positive (1), errors negative (easier to test in Dart)
typedef enum {
    RECORDER_OK                       = 1,
    RECORDER_ERROR_UNKNOWN            = -1,
    RECORDER_ERROR_OUT_OF_MEMORY      = -2,
    RECORDER_ERROR_INVALID_ARGUMENT   = -3,
    RECORDER_ERROR_ALREADY_RECORDING  = -4,
    RECORDER_ERROR_NOT_RECORDING      = -5,
    RECORDER_ERROR_INVALID_FORMAT     = -6,
    RECORDER_ERROR_INVALID_CHANNELS   = -7
} RecorderResult;

EXPORT Recorder *recorder_create(void);
EXPORT RecorderResult recorder_init_file(Recorder *recorder, const char *filename,
                                         int sample_rate, int channels, ma_format format);
EXPORT RecorderResult recorder_init_stream(Recorder *recorder,
                                           int sample_rate, int channels, ma_format format,
                                           int buffer_duration_seconds);
EXPORT RecorderResult recorder_start(Recorder *recorder);
EXPORT RecorderResult recorder_stop(Recorder *recorder);
EXPORT int  recorder_get_available_frames(Recorder *recorder);
// Optional (explicit ring buffer accessor)
EXPORT int  recorder_get_available_frames_rb(Recorder *recorder);
EXPORT int  recorder_get_buffer(Recorder *recorder, float *output, int floats_to_read); // legacy
EXPORT bool recorder_is_recording(const Recorder *recorder);
EXPORT void recorder_destroy(Recorder *recorder);

// Streaming (ring buffer) helpers
EXPORT int recorder_acquire_read_region(Recorder* r, uintptr_t* outPtr, int* outFrames);
/* Returns 1 on success (including the case of no data: *outFrames==0, *outPtr==0),
   0 on internal error. */
EXPORT int recorder_commit_read_frames(Recorder* r, int frames);

/* Capture device enumeration / selection */
EXPORT int       recorder_refresh_capture_devices(Recorder* r);
EXPORT ma_uint32 recorder_get_capture_device_count(Recorder* r);
EXPORT int       recorder_get_capture_device_name(Recorder* r,
                                                  ma_uint32 index,
                                                  char* outName,
                                                  ma_uint32 capName,
                                                  ma_bool32* pIsDefault);
EXPORT int       recorder_select_capture_device_by_index(Recorder* r, ma_uint32 index);
/* Generation counter (increments when devices refreshed or switched) */
EXPORT ma_uint32 recorder_get_capture_device_generation(Recorder* r);
EXPORT void recorder_free_capture_cache(Recorder* r);

/* Exported inline encoder control API */
EXPORT int recorder_attach_inline_opus(Recorder* r, int sample_rate, int channels);
EXPORT int recorder_detach_inline_encoder(Recorder* r);
EXPORT int recorder_encoder_dequeue_packet(Recorder* r, void* outBuf, int cap);
EXPORT uint32_t recorder_encoder_pending(Recorder* r);
EXPORT int recorder_inline_encoder_feed_f32(Recorder* r, const float* interleaved, int frameCount);
/* padWithZeros: 1 => pad and emit residual, 0 => only emit if full frame */
EXPORT int recorder_inline_encoder_flush(Recorder* r, int padWithZeros);

#endif // RECORD_H
