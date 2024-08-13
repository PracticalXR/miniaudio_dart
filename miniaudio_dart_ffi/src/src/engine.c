#include "../include/engine.h"

#include <stdbool.h>
#include <stdlib.h>

#include "../include/miniaudio.h"

/*************
 ** private **
 *************/

struct Engine
{
    bool is_started;

    ma_engine engine;
    ma_decoder_config dec_config;
};

/************
 ** public **
 ************/

Engine *engine_alloc()
{
    Engine *const engine = malloc(sizeof(Engine));
    return engine;
}

int engine_init(Engine *const self, uint32_t const period_ms)
{
    self->is_started = false;

    ma_engine_config engine_config = ma_engine_config_init();
    engine_config.periodSizeInMilliseconds = period_ms;
    engine_config.noAutoStart = true;
    if (ma_engine_init(&engine_config, &self->engine) != MA_SUCCESS)
        return 0;

    self->dec_config = ma_decoder_config_init(
        self->engine.pDevice->playback.format,
        self->engine.pDevice->playback.channels,
        self->engine.sampleRate);

    return 1;
}
void engine_uninit(Engine *const self) { ma_engine_uninit(&self->engine); }

int engine_start(Engine *const self)
{
    if (self->is_started)
        return 1;

    if (ma_engine_start(&self->engine) != MA_SUCCESS)
        return 0;

    self->is_started = true;
    
    return 1;
}

int engine_load_sound(
    Engine *const self,
    Sound *const sound,
    float *data,
    size_t const data_size,
    ma_format format,
    int sample_rate,
    int channels)
{
    return sound_init(sound, data, data_size, format, channels, sample_rate, &self->engine);
}
