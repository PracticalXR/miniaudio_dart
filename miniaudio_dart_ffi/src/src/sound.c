#include "../include/sound.h"
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include "../include/miniaudio.h"

Sound *sound_alloc()
{
    Sound *const sound = malloc(sizeof(Sound));
    return sound;
}

int sound_init(
    Sound *const self,
    float *data,
    size_t const data_size,
    const ma_format format,
    const int channels,
    const int sample_rate,
    ma_engine *const engine)
{
    self->engine = engine;
    self->is_looped = false;
    self->loop_delay_ms = 0;
    self->owned_data = NULL;
    self->owned_size = 0;

    // Always make an internal copy so the data source has stable memory.
    if (data != NULL && data_size > 0) {
        self->owned_data = malloc(data_size);
        if (self->owned_data == NULL) return 0;
        memcpy(self->owned_data, (const void*)data, data_size);
        self->owned_size = data_size;
    }

    if (format != ma_format_unknown && channels > 0 && sample_rate > 0)
    {
        // RAW PCM path: use ma_audio_buffer so the engine can resample to its rate.
        self->is_raw_data = true;

        // Compute frame count from byte size.
        ma_uint32 bps = (ma_uint32)ma_get_bytes_per_sample(format);
        ma_uint32 ch  = (ma_uint32)channels;
        ma_uint64 frames = 0;
        if (bps != 0 && ch != 0) {
            ma_uint64 bytesPerFrame = (ma_uint64)bps * (ma_uint64)ch;
            frames = (ma_uint64)(self->owned_size / bytesPerFrame);
        }

        ma_audio_buffer_config cfg =
            ma_audio_buffer_config_init(
                format,
                ch,
                frames,                 // sizeInFrames
                self->owned_data,       // pData
                NULL);                  // pAllocationCallbacks

        if (ma_audio_buffer_init(&cfg, &self->buffer) != MA_SUCCESS) {
            free(self->owned_data); self->owned_data = NULL; self->owned_size = 0;
            return 0;
        }

        if (ma_sound_init_from_data_source(
                engine,
                (ma_data_source*)&self->buffer,
                MA_SOUND_FLAG_NO_PITCH | MA_SOUND_FLAG_NO_SPATIALIZATION,
                NULL,
                &self->sound) != MA_SUCCESS) {
            ma_audio_buffer_uninit(&self->buffer);
            free(self->owned_data); self->owned_data = NULL; self->owned_size = 0;
            return 0;
        }
    }
    else
    {
        // Encoded audio path (WAV/OGG/etc.)
        self->is_raw_data = false;

        if (ma_decoder_init_memory(self->owned_data, self->owned_size, NULL, &self->decoder) != MA_SUCCESS) {
            free(self->owned_data); self->owned_data = NULL; self->owned_size = 0;
            return 0;
        }

        if (ma_sound_init_from_data_source(
                engine,
                (ma_data_source*)&self->decoder,
                MA_SOUND_FLAG_NO_PITCH | MA_SOUND_FLAG_NO_SPATIALIZATION,
                NULL,
                &self->sound) != MA_SUCCESS) {
            ma_decoder_uninit(&self->decoder);
            free(self->owned_data); self->owned_data = NULL; self->owned_size = 0;
            return 0;
        }
    }

    return 1;
}

void sound_unload(Sound *const self)
{
    if (self->is_raw_data) {
        ma_sound_uninit(&self->sound);
        ma_audio_buffer_uninit(&self->buffer);
    } else {
        ma_sound_uninit(&self->sound);
        ma_decoder_uninit(&self->decoder);
    }
    if (self->owned_data) {
        free(self->owned_data);
        self->owned_data = NULL;
        self->owned_size = 0;
    }
}

int sound_play(Sound *const self)
{
    ma_sound *sound = &self->sound;
    if (ma_sound_start(sound) != MA_SUCCESS)
        return 0;

    return 1;
}

int sound_replay(Sound *const self)
{
    sound_stop(self);
    return sound_play(self);
}

void sound_pause(Sound *const self)
{
    ma_sound *sound = &self->sound;
    ma_sound_stop(sound);
}

void sound_stop(Sound *const self)
{
    ma_sound *sound = &self->sound;
    ma_sound_stop(sound);
    ma_sound_seek_to_pcm_frame(sound, 0);
}

float sound_get_volume(Sound const *const self)
{
    // Avoid discarding qualifiers warning.
    return ma_sound_get_volume(&self->sound);
}

void sound_set_volume(Sound *const self, float const value)
{
    ma_sound *sound = &self->sound;
    ma_sound_set_volume(sound, value);
}

float sound_get_duration(Sound *const self)
{
    ma_uint64 length_in_frames;
    if (self->is_raw_data)
    {
        ma_audio_buffer_get_length_in_pcm_frames(&self->buffer, &length_in_frames);
    }
    else
    {
        ma_sound_get_length_in_pcm_frames(&self->sound, &length_in_frames);
    }
    return (float)length_in_frames / ma_engine_get_sample_rate(self->engine);
}

bool sound_get_is_looped(Sound const *const self)
{
    return self->is_looped;
}

void sound_set_looped(
    Sound *const self,
    bool const value,
    size_t const delay_ms)
{
    // Track state
    self->is_looped = value;
    self->loop_delay_ms = (int)delay_ms;

    // Choose the actual data source we wrapped the ma_sound with.
    ma_data_source* src = self->is_raw_data
        ? (ma_data_source*)&self->buffer
        : (ma_data_source*)&self->decoder;

    if (!value) {
        // Turn off looping and break any chain.
        ma_data_source_set_looping(src, false);
        ma_data_source_set_next(src, NULL);
        ma_data_source_set_next((ma_data_source*)&self->loop_delay_ds, NULL);
        // Reset the current pointer to the head (optional, but safe).
        ma_data_source_set_current(src, src);
        return;
    }

    if (delay_ms == 0) {
        // Simple seamless loop on the current source.
        ma_data_source_set_looping(src, true);
        return;
    }

    // Delayed loop: src -> silence(delay) -> src
    ma_format fmt = ma_format_unknown;
    ma_uint32 ch = 0;
    ma_uint32 sr = 0;
    ma_data_source_get_data_format(src, &fmt, &ch, &sr, NULL, 0);

    ma_uint64 delayFrames = ((ma_uint64)delay_ms * sr) / 1000;

    SilenceDataSourceConfig const cfg =
        silence_data_source_config(fmt, (int)ch, (int)sr, delayFrames);

    // (Re)initialize delay data source (idempotent if your impl handles it).
    silence_data_source_init(&self->loop_delay_ds, &cfg);

    ma_data_source_set_looping(src, false); // chaining handles the loop
    ma_data_source_set_next(src, (ma_data_source*)&self->loop_delay_ds);
    ma_data_source_set_next((ma_data_source*)&self->loop_delay_ds, src);
}
