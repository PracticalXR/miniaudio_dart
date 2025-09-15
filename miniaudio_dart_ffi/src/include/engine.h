#ifndef ENGINE_H
#define ENGINE_H

#include <stdint.h>

#include "../external/miniaudio/include/miniaudio.h"
#include "export.h"
#include "sound.h"

typedef struct Engine Engine;

EXPORT Engine *engine_alloc();
EXPORT int engine_init(Engine *const self, uint32_t const period_ms);
EXPORT void engine_uninit(Engine *const self);
EXPORT int engine_start(Engine *const self);
EXPORT int engine_load_sound(
    Engine *const self,
    Sound *const sound,
    float *data,
    size_t const data_size,
    ma_format format,
    int sample_rate,
    int channels
);
EXPORT ma_engine* engine_get_ma_engine(Engine *const self);

typedef struct PlaybackDeviceInfo {
    char name[256];
    ma_bool32 isDefault;
    ma_device_id id; // opaque bytes; used internally for selection
} PlaybackDeviceInfo;

EXPORT int engine_refresh_playback_devices(Engine* self);
EXPORT ma_uint32 engine_get_playback_device_count(Engine* self);
EXPORT int engine_get_playback_device_name(Engine* self, ma_uint32 index, char* outName, ma_uint32 capName, ma_bool32* pIsDefault);
EXPORT int engine_select_playback_device_by_index(Engine* self, ma_uint32 index);

#endif
