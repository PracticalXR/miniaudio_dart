#ifndef SOUND_H
#define SOUND_H

#include <stdbool.h>
#include <stddef.h>

#include "../external/miniaudio/include/miniaudio.h"
#include "export.h"
#include "silence_data_source.h"

typedef struct Sound {
    ma_engine *engine;
    ma_sound sound;

    bool is_raw_data;
    ma_audio_buffer buffer;
    ma_decoder decoder;

    bool is_looped;
    int  loop_delay_ms;
    SilenceDataSource loop_delay_ds;

    // Own a copy of the input bytes for decoder/buffer lifetime
    void*  owned_data;
    size_t owned_size;
} Sound;

EXPORT Sound *sound_alloc();

int sound_init(
    Sound *const self,
    float *data,
    size_t const data_size,
    const ma_format format,
    const int channels,
    const int sample_rate,
    ma_engine *const engine);
EXPORT void sound_unload(Sound *const self);

EXPORT int sound_play(Sound *const self);
EXPORT int sound_replay(Sound *const self);
EXPORT void sound_pause(Sound *const self);
EXPORT void sound_stop(Sound *const self);

EXPORT float sound_get_volume(Sound const *const self);
EXPORT void sound_set_volume(Sound *const self, float const value);

EXPORT float sound_get_duration(Sound *const self);

EXPORT bool sound_get_is_looped(Sound const *const self);
EXPORT void sound_set_looped(Sound *const self, bool const value, size_t const delay_ms);

#endif
