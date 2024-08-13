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

#endif
