#include "../include/engine.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h> // <- add this

#include "../include/miniaudio.h"

/*************
 ** private **
 *************/

struct Engine
{
    bool is_started;

    ma_engine engine;
    ma_decoder_config dec_config;

    // New: device enumeration/cache
    ma_context context;
    PlaybackDeviceInfo* playbackInfos;
    ma_uint32 playbackCount;
};

static void engine_free_playback_cache(Engine* self) {
    if (self->playbackInfos != NULL) {
        free(self->playbackInfos);
        self->playbackInfos = NULL;
        self->playbackCount = 0;
    }
}

/************
 ** public **
 ************/

Engine *engine_alloc()
{
    Engine *const engine = malloc(sizeof(Engine));
    if (engine) {
        engine->playbackInfos = NULL;
        engine->playbackCount = 0;
    }
    return engine;
}

int engine_init(Engine *const self, uint32_t const period_ms)
{
    self->is_started = false;
    self->playbackInfos = NULL;
    self->playbackCount = 0;

    // Init a shared context so we can enumerate/select devices.
    ma_context_config ctxCfg = ma_context_config_init();
    if (ma_context_init(NULL, 0, &ctxCfg, &self->context) != MA_SUCCESS)
        return 0;

    ma_engine_config engine_config = ma_engine_config_init();
    engine_config.periodSizeInMilliseconds = period_ms;
    engine_config.noAutoStart = true;
    engine_config.pContext = &self->context; // ensure same context
    if (ma_engine_init(&engine_config, &self->engine) != MA_SUCCESS) {
        ma_context_uninit(&self->context);
        return 0;
    }

    self->dec_config = ma_decoder_config_init(
        self->engine.pDevice->playback.format,
        self->engine.pDevice->playback.channels,
        self->engine.sampleRate);

    // Cache devices once at init; caller can refresh later.
    engine_refresh_playback_devices(self);
    return 1;
}

void engine_uninit(Engine *const self) {
    ma_engine_uninit(&self->engine);
    engine_free_playback_cache(self);
    ma_context_uninit(&self->context);
}

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

// Enumerate and cache playback devices.
int engine_refresh_playback_devices(Engine* self) {
    if (self == NULL) return 0;
    engine_free_playback_cache(self);

    ma_result res;
    ma_device_info* pPlaybackInfos = NULL;
    ma_uint32 playbackCount = 0;
    ma_device_info* pCaptureInfos = NULL;
    ma_uint32 captureCount = 0;

    res = ma_context_get_devices(&self->context,
                                 &pPlaybackInfos, &playbackCount,
                                 &pCaptureInfos, &captureCount);
    if (res != MA_SUCCESS) {
        return 0;
    }

    if (playbackCount == 0) {
        self->playbackInfos = NULL;
        self->playbackCount = 0;
        return 1;
    }

    self->playbackInfos = (PlaybackDeviceInfo*)malloc(sizeof(PlaybackDeviceInfo) * playbackCount);
    if (self->playbackInfos == NULL) {
        self->playbackCount = 0;
        return 0;
    }

    for (ma_uint32 i = 0; i < playbackCount; ++i) {
        PlaybackDeviceInfo* dst = &self->playbackInfos[i];
        ma_device_info* src = &pPlaybackInfos[i];
        // Copy friendly name
        size_t n = strlen(src->name);
        if (n >= sizeof(dst->name)) n = sizeof(dst->name) - 1;
        memcpy(dst->name, src->name, n);
        dst->name[n] = '\0';
        // Copy default flag and id
        dst->isDefault = src->isDefault;
        dst->id = src->id; // struct copy
    }
    self->playbackCount = playbackCount;
    return 1;
}

ma_uint32 engine_get_playback_device_count(Engine* self) {
    return self ? self->playbackCount : 0;
}

int engine_get_playback_device_name(Engine* self, ma_uint32 index, char* outName, ma_uint32 capName, ma_bool32* pIsDefault) {
    if (!self || index >= self->playbackCount || !outName || capName == 0) return 0;
    PlaybackDeviceInfo* info = &self->playbackInfos[index];
    size_t n = strlen(info->name);
    if (n >= capName) n = capName - 1;
    memcpy(outName, info->name, n);
    outName[n] = '\0';
    if (pIsDefault) *pIsDefault = info->isDefault;
    return 1;
}

// Recreate engine on selected playback device. Caller should stop sounds/players first.
int engine_select_playback_device_by_index(Engine* self, ma_uint32 index) {
    if (!self || index >= self->playbackCount) return 0;

    // Preserve state
    bool was_started = self->is_started;

    if (was_started) {
        ma_engine_stop(&self->engine);
        self->is_started = false;
    }
    ma_engine_uninit(&self->engine);

    ma_engine_config engine_config = ma_engine_config_init();
    engine_config.noAutoStart = true;
    engine_config.pContext = &self->context;
    // Use the selected device id
    engine_config.pPlaybackDeviceID = &self->playbackInfos[index].id;

    if (ma_engine_init(&engine_config, &self->engine) != MA_SUCCESS) {
        // Try to fall back to default device
        ma_engine_config fallback = ma_engine_config_init();
        fallback.noAutoStart = true;
        fallback.pContext = &self->context;
        if (ma_engine_init(&fallback, &self->engine) != MA_SUCCESS) {
            return 0;
        }
    }

    self->dec_config = ma_decoder_config_init(
        self->engine.pDevice->playback.format,
        self->engine.pDevice->playback.channels,
        self->engine.sampleRate);

    if (was_started) {
        if (ma_engine_start(&self->engine) != MA_SUCCESS) {
            return 0;
        }
        self->is_started = true;
    }
    return 1;
}

ma_engine* engine_get_ma_engine(Engine *const self)
{
    if (self == NULL) return NULL;
    return &self->engine;
}
