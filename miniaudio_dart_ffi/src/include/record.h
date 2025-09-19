#ifndef RECORD_H
#define RECORD_H

#include <stdint.h>
#if __has_include("../external/miniaudio/include/miniaudio.h")
#include "../external/miniaudio/include/miniaudio.h"
#elif __has_include("miniaudio.h")
#include "miniaudio.h"
#else
#error "miniaudio.h not found"
#endif
#include "codec.h"
#include "crosscoder.h"
#include "export.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Recorder Recorder;

typedef enum RecorderCodec {
    RECORDER_CODEC_PCM = 0,  /* Default - raw PCM frames */
    RECORDER_CODEC_OPUS = 1  /* Opus encoded packets */
} RecorderCodec;

typedef struct RecorderCodecConfig {
    RecorderCodec codec;
    int           opusApplication;  /* OPUS_APPLICATION_AUDIO = 2049 */
    int           opusBitrate;      /* Target bitrate for Opus */
    int           opusComplexity;   /* 0-10, default 5 */
    int           opusVBR;          /* 1 = VBR, 0 = CBR */
} RecorderCodecConfig;

typedef struct RecorderConfig {
    int                   sampleRate;
    int                   channels;
    ma_format             format;
    int                   bufferDurationSeconds;
    RecorderCodecConfig*  codecConfig;  /* NULL = PCM default */
    int                   autoStart;
} RecorderConfig;

EXPORT RecorderConfig recorder_config_default(int sampleRate,
                                              int channels,
                                              ma_format format);

EXPORT RecorderCodecConfig recorder_codec_config_opus_default(void);

EXPORT Recorder* recorder_create(void);
EXPORT void      recorder_destroy(Recorder* r);
EXPORT int       recorder_init(Recorder* r, const RecorderConfig* cfg);
EXPORT int       recorder_start(Recorder* r);
EXPORT int       recorder_stop(Recorder* r);
EXPORT int       recorder_is_recording(const Recorder* r);

/* Unified read API - returns PCM frames or encoded packets based on codec */
EXPORT int recorder_get_available_frames(Recorder* r);
EXPORT int recorder_acquire_read_region(Recorder* r, void** outPtr, int* outFrames);
EXPORT int recorder_commit_read_frames(Recorder* r, int frames);

EXPORT void  recorder_set_capture_gain(Recorder* r, float gain);
EXPORT float recorder_get_capture_gain(Recorder* r);

/* Query codec in use */
EXPORT RecorderCodec recorder_get_codec(Recorder* r);

/* Dynamic codec configuration changes */
EXPORT int recorder_update_codec_config(Recorder* r, const RecorderCodecConfig* codecConfig);

/* Device enumeration and selection APIs */
EXPORT int       recorder_refresh_capture_devices(Recorder* r);
EXPORT ma_uint32 recorder_get_capture_device_count(Recorder* r);
EXPORT int       recorder_get_capture_device_name(Recorder* r,
                                                  ma_uint32 index,
                                                  char* outName,
                                                  ma_uint32 capName,
                                                  ma_bool32* pIsDefault);
EXPORT int       recorder_select_capture_device_by_index(Recorder* r, ma_uint32 index);
EXPORT ma_uint32 recorder_get_capture_device_generation(Recorder* r);
EXPORT void      recorder_free_capture_cache(Recorder* r);

#ifdef __cplusplus
}
#endif
#endif /* RECORD_H */
