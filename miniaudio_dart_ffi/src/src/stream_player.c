#include "../include/stream_player.h"
#include "../include/engine.h"  // for Engine* helper
#include "../include/codec_runtime.h"
#include "../include/codec_packet_format.h"
#include <string.h>
#include <stddef.h> // offsetof

// container-of to recover sp_data_source from ma_data_source*
#define SP_CONTAINER_OF(ptr, type, member) ((type*)((char*)(ptr) - offsetof(type, member)))

typedef struct {
    // Use the public base type, not the opaque ma_data_source.
    ma_data_source_base base;
    struct StreamPlayer* owner;
} sp_data_source;

struct StreamPlayer {
    ma_engine* engine;
    ma_sound   sound;

    ma_format  format;
    ma_uint32  channels;
    ma_uint32  sampleRate;
    ma_uint32  frameSize; // bytes per frame

    ma_pcm_rb  rb;
    sp_data_source ds;

    ma_bool32  started;
    float      volume;

    CodecRuntime codecRT;
    int          codecRTInitialized;
};

/******** vtable callbacks ********/

static ma_result sp_on_read(ma_data_source* pDS, void* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead)
{
    sp_data_source* ds = SP_CONTAINER_OF(pDS, sp_data_source, base);
    StreamPlayer* sp = ds->owner;

    ma_uint8* out = (ma_uint8*)pFramesOut;
    ma_uint64 framesRemaining = frameCount;

    while (framesRemaining > 0) {
        ma_uint32 req = (ma_uint32)((framesRemaining > 0x7FFFFFFF) ? 0x7FFFFFFF : framesRemaining);
        void* pRead = NULL;
        if (ma_pcm_rb_acquire_read(&sp->rb, &req, &pRead) != MA_SUCCESS || req == 0) {
            // Underrun: fill remainder with silence to keep clock running.
            const ma_uint64 bytesRemain = framesRemaining * sp->frameSize;
            memset(out, 0, (size_t)bytesRemain);
            out += bytesRemain;
            framesRemaining = 0;
            break;
        }

        memcpy(out, pRead, (size_t)req * sp->frameSize);
        ma_pcm_rb_commit_read(&sp->rb, req);
        out += (size_t)req * sp->frameSize;
        framesRemaining -= req;
    }

    if (pFramesRead) *pFramesRead = frameCount;
    return MA_SUCCESS;
}

static ma_result sp_on_seek(ma_data_source* pDS, ma_uint64 frameIndex)
{
    sp_data_source* ds = SP_CONTAINER_OF(pDS, sp_data_source, base);
    StreamPlayer* sp = ds->owner;
    if (frameIndex == 0) {
        ma_pcm_rb_reset(&sp->rb);
        return MA_SUCCESS;
    }
    return MA_INVALID_OPERATION;
}

static ma_result sp_on_get_data_format(ma_data_source* pDS,
                                       ma_format* pFormat, ma_uint32* pChannels, ma_uint32* pSampleRate,
                                       ma_channel* pChannelMap, size_t channelMapCap)
{
    sp_data_source* ds = SP_CONTAINER_OF(pDS, sp_data_source, base);
    StreamPlayer* sp = ds->owner;
    if (pFormat)     *pFormat = sp->format;
    if (pChannels)   *pChannels = sp->channels;
    if (pSampleRate) *pSampleRate = sp->sampleRate;
    (void)pChannelMap; (void)channelMapCap;
    return MA_SUCCESS;
}

// Static vtable for our data source
static ma_data_source_vtable g_sp_vtable = {
    sp_on_read,
    sp_on_seek,
    sp_on_get_data_format,
    NULL  // onGetCursor (optional)
};

/******** public API ********/

StreamPlayer* stream_player_alloc() {
    StreamPlayer* sp = (StreamPlayer*)ma_malloc(sizeof(StreamPlayer), NULL);
    return sp;
}

void stream_player_free(StreamPlayer* self) {
    if (self) {
        ma_free(self, NULL);
    }
}

int stream_player_init(StreamPlayer* self,
                       ma_engine* engine,
                       ma_format format, int channels, int sample_rate,
                       uint32_t buffer_ms)
{
    if (self == NULL || engine == NULL) return 0;

    self->engine = engine;
    self->format = format;
    self->channels = (ma_uint32)channels;
    self->sampleRate = (ma_uint32)sample_rate;
    self->frameSize = (ma_uint32)(ma_get_bytes_per_sample(format) * channels);
    self->started = MA_FALSE;
    self->volume = 1.0f;

    // Ring buffer capacity in frames.
    ma_uint64 capacityFrames = ((ma_uint64)buffer_ms * self->sampleRate) / 1000;
    if (capacityFrames < 1024) capacityFrames = 1024; // minimum

    // Note: provide all args, including allocation callbacks.
    if (ma_pcm_rb_init(self->format,
                       self->channels,
                       (ma_uint32)capacityFrames,
                       NULL,            // pOptionalPreallocatedBuffer
                       NULL,            // pAllocationCallbacks
                       &self->rb) != MA_SUCCESS)
    {
        return 0;
    }

    // Initialize data source base with our vtable.
    self->ds.owner = self;
    ma_data_source_config cfg = ma_data_source_config_init();
    cfg.vtable = &g_sp_vtable;
    if (ma_data_source_init(&cfg, (ma_data_source*)&self->ds.base) != MA_SUCCESS) {
        ma_pcm_rb_uninit(&self->rb);
        return 0;
    }

    // Hook into engine as a sound from data source.
    if (ma_sound_init_from_data_source(
            engine,
            (ma_data_source*)&self->ds.base,
            MA_SOUND_FLAG_NO_PITCH | MA_SOUND_FLAG_NO_SPATIALIZATION,
            NULL,
            &self->sound) != MA_SUCCESS)
    {
        ma_data_source_uninit((ma_data_source*)&self->ds.base);
        ma_pcm_rb_uninit(&self->rb);
        return 0;
    }

    ma_sound_set_volume(&self->sound, self->volume);

    CodecConfig cc = { .sample_rate = self->sampleRate, .channels = self->channels, .bits_per_sample = 32 };
    if (codec_runtime_init(&self->codecRT, CODEC_ID_NONE, &cc)) {
        self->codecRTInitialized = 1;
    } else {
        self->codecRTInitialized = 0;
    }

    return 1;
}

void stream_player_uninit(StreamPlayer* self)
{
    if (!self) return;
    ma_sound_uninit(&self->sound);
    ma_data_source_uninit((ma_data_source*)&self->ds.base);
    ma_pcm_rb_uninit(&self->rb);

    if (self->codecRTInitialized) {
        codec_runtime_uninit(&self->codecRT);
        self->codecRTInitialized = 0;
    }
}

int stream_player_start(StreamPlayer* self)
{
    if (!self) return 0;
    if (self->started) return 1;
    if (ma_sound_start(&self->sound) != MA_SUCCESS) return 0;
    self->started = MA_TRUE;
    return 1;
}

int stream_player_stop(StreamPlayer* self)
{
    if (!self) return 0;
    if (!self->started) return 1;
    ma_sound_stop(&self->sound);
    self->started = MA_FALSE;
    return 1;
}

void stream_player_clear(StreamPlayer* self)
{
    if (!self) return;
    ma_pcm_rb_reset(&self->rb);
}

void stream_player_set_volume(StreamPlayer* self, float volume)
{
    if (!self) return;
    self->volume = volume;
    ma_sound_set_volume(&self->sound, volume);
}

size_t stream_player_write_frames_f32(StreamPlayer* self,
                                      const float* interleaved,
                                      size_t frames)
{
    if (!self || !interleaved || frames == 0) return 0;

    size_t totalWritten = 0;
    const size_t bytesPerFrame = self->frameSize;

    while (totalWritten < frames) {
        ma_uint32 space = ma_pcm_rb_available_write(&self->rb);
        if (space == 0) {
            // Buffer is full: drop newest input to avoid corruption/glitches.
            break;
        }

        ma_uint32 req = (ma_uint32)((frames - totalWritten) < space ? (frames - totalWritten) : space);
        void* pWrite = NULL;
        if (ma_pcm_rb_acquire_write(&self->rb, &req, &pWrite) != MA_SUCCESS || req == 0) break;

        memcpy(pWrite,
               (const ma_uint8*)interleaved + (totalWritten * bytesPerFrame),
               (size_t)req * bytesPerFrame);

        ma_pcm_rb_commit_write(&self->rb, req);
        totalWritten += req;
    }

    return totalWritten;
}

int stream_player_init_with_engine(StreamPlayer* self,
                                   Engine* engine,
                                   ma_format format, int channels, int sample_rate,
                                   uint32_t buffer_ms)
{
    if (self == NULL || engine == NULL) return 0;
    ma_engine* mae = engine_get_ma_engine(engine);
    if (mae == NULL) return 0;
    // Forward to the standard initializer that takes a ma_engine*
    return stream_player_init(self, mae, format, channels, sample_rate, buffer_ms);
}

int stream_player_push_encoded_packet(StreamPlayer* sp,
                                      const void* data,
                                      int len)
{
    if (!sp || !data || len <= CODEC_FRAME_HEADER_BYTES) return 0;
    if (!sp->codecRTInitialized) {
        CodecConfig cc = { .sample_rate = sp->sampleRate, .channels = sp->channels, .bits_per_sample = 32 };
        if (!codec_runtime_init(&sp->codecRT, CODEC_ID_NONE, &cc))
            return 0;
        sp->codecRTInitialized = 1;
    }
    return codec_runtime_push_packet(&sp->codecRT,
                                     (const uint8_t*)data,
                                     len,
                                     sp);
}