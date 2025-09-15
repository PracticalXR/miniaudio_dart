#ifndef ENGINE_H
#define ENGINE_H

#include <stdint.h>
#include <stdbool.h>
#include "../external/miniaudio/include/miniaudio.h"
#include "export.h"
#include "sound.h"

typedef struct Engine Engine;


// Playback device info (mirrors internal cache entry)
typedef struct {
    char        name[256];
    ma_device_id id;
    ma_bool32   isDefault;
} PlaybackDeviceInfo;

// playback device generation accessor
EXPORT ma_uint32 engine_get_playback_device_generation(Engine* self);

EXPORT Engine*  engine_alloc(void);
EXPORT void     engine_free(Engine* self);
EXPORT int      engine_init(Engine* self, uint32_t period_ms);
EXPORT void     engine_uninit(Engine* self);
EXPORT int      engine_start(Engine* self);
EXPORT int      engine_load_sound(Engine* self,
                                  struct Sound* sound,
                                  float* data,
                                  size_t data_size,
                                  ma_format format,
                                  int sample_rate,
                                  int channels);

// playback device enumeration/selection
EXPORT int       engine_refresh_playback_devices(Engine* self);
EXPORT ma_uint32 engine_get_playback_device_count(Engine* self);
EXPORT int       engine_get_playback_device_name(Engine* self,
                                                 ma_uint32 index,
                                                 char* outName,
                                                 ma_uint32 capName,
                                                 ma_bool32* pIsDefault);
EXPORT int       engine_select_playback_device_by_index(Engine* self,
                                                        ma_uint32 index);

EXPORT ma_engine* engine_get_ma_engine(Engine* self);

#endif
