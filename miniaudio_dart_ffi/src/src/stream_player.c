#include "../include/stream_player.h"
#include "../include/engine.h"
#include <stdlib.h>
#include <string.h>
#include <stddef.h>

/* Data source wrapper */
typedef struct {
    ma_data_source_base base;
    struct StreamPlayer* owner;
} sp_data_source;

struct StreamPlayer {
    ma_engine*      engine;
    ma_sound        sound;
    ma_pcm_rb       rb;

    ma_format       format;
    ma_uint32       channels;
    ma_uint32       sampleRate;
    ma_uint32       frameSizeBytes;

    sp_data_source  ds;
    int             started;
    float           volume;
    int             initialized;  // Add initialization flag

    CodecRuntime    codecRT;
    int             codecInitialized;
    int             allowCodecPackets;

    float*          decodeBuf;
    int             decodeBufFrames;
};

#define SP_CONTAINER_OF(ptr, type, member) ((type*)((char*)(ptr) - offsetof(type, member)))

static ma_result sp_on_read(ma_data_source* pDS,
                            void* pFramesOut,
                            ma_uint64 frameCount,
                            ma_uint64* pFramesRead)
{
    sp_data_source* dsw = SP_CONTAINER_OF(pDS, sp_data_source, base);
    StreamPlayer* sp = dsw->owner;
    ma_uint8* out = (ma_uint8*)pFramesOut;
    ma_uint64 remaining = frameCount;

    while(remaining > 0) {
        ma_uint32 req = (ma_uint32)((remaining > 0x7FFFFFFF) ? 0x7FFFFFFF : remaining);
        void* pRead = NULL;
        if(ma_pcm_rb_acquire_read(&sp->rb, &req, &pRead) != MA_SUCCESS || req == 0) {
            /* Underrun: fill silence */
            size_t silenceBytes = (size_t)remaining * sp->frameSizeBytes;
            memset(out, 0, silenceBytes);
            out += silenceBytes;
            remaining = 0;
            break;
        }
        memcpy(out, pRead, (size_t)req * sp->frameSizeBytes);
        ma_pcm_rb_commit_read(&sp->rb, req);
        out += (size_t)req * sp->frameSizeBytes;
        remaining -= req;
    }
    if(pFramesRead) *pFramesRead = frameCount;
    return MA_SUCCESS;
}

static ma_result sp_on_seek(ma_data_source* pDS, ma_uint64 frameIndex) {
    (void)pDS;
    (void)frameIndex;
    return MA_INVALID_OPERATION;
}

static ma_result sp_on_format(ma_data_source* pDS,
                              ma_format* pFormat,
                              ma_uint32* pChannels,
                              ma_uint32* pSampleRate,
                              ma_channel* pChannelMap,
                              size_t channelMapCap)
{
    (void)pChannelMap; (void)channelMapCap;
    sp_data_source* dsw = SP_CONTAINER_OF(pDS, sp_data_source, base);
    StreamPlayer* sp = dsw->owner;
    if(pFormat)     *pFormat    = sp->format;
    if(pChannels)   *pChannels  = sp->channels;
    if(pSampleRate) *pSampleRate= sp->sampleRate;
    return MA_SUCCESS;
}

static ma_data_source_vtable g_sp_vtable = {
    sp_on_read,
    sp_on_seek,
    sp_on_format,
    NULL
};

StreamPlayerConfig stream_player_config_default(int channels, int sampleRate) {
    StreamPlayerConfig cfg;
    cfg.format             = ma_format_f32;
    cfg.channels           = channels;
    cfg.sampleRate         = sampleRate;
    cfg.bufferMilliseconds = 200;
    cfg.allowCodecPackets  = 1;
    cfg.decodeAccumFrames  = 0;
    return cfg;
}

static int sp_realloc_decode_buf(StreamPlayer* sp, int frames) {
    if(frames <= sp->decodeBufFrames) return 1;
    float* nb = (float*)realloc(sp->decodeBuf,
                      (size_t)frames * sp->channels * sizeof(float));
    if(!nb) return 0;
    sp->decodeBuf = nb;
    sp->decodeBufFrames = frames;
    return 1;
}

StreamPlayer* stream_player_alloc(void) {
    // Use ma_malloc to match ma_free
    StreamPlayer* sp = (StreamPlayer*)ma_malloc(sizeof(StreamPlayer), NULL);
    if (sp) {
        memset(sp, 0, sizeof(StreamPlayer));
    }
    return sp;
}

void stream_player_free(StreamPlayer* sp) {
    if(!sp) return;
    stream_player_uninit(sp);
    if (sp->decodeBuf) {
        ma_free(sp->decodeBuf, NULL);
    }
    ma_free(sp, NULL);  // Use ma_free to match ma_malloc
}

int stream_player_init(StreamPlayer* sp,
                       ma_engine* engine,
                       const StreamPlayerConfig* cfg)
{
    if(!sp || !engine || !cfg) return 0;
    if(sp->initialized) return 0;  // Prevent double-init

    sp->engine     = engine;
    sp->format     = cfg->format;
    sp->channels   = (ma_uint32)cfg->channels;
    sp->sampleRate = (ma_uint32)cfg->sampleRate;
    sp->frameSizeBytes = (ma_uint32)(ma_get_bytes_per_sample(sp->format) * sp->channels);
    sp->volume     = 1.0f;
    sp->allowCodecPackets = cfg->allowCodecPackets ? 1 : 0;

    ma_uint64 capacityFrames = ((ma_uint64)cfg->bufferMilliseconds * sp->sampleRate) / 1000;
    if(capacityFrames < 1024) capacityFrames = 1024;
    if(capacityFrames > 0x7FFFFFFFULL) capacityFrames = 0x7FFFFFFF;

    if(ma_pcm_rb_init(sp->format,
                      sp->channels,
                      (ma_uint32)capacityFrames,
                      NULL,
                      NULL,
                      &sp->rb) != MA_SUCCESS) {
        return 0;
    }

    sp->ds.owner = sp;
    ma_data_source_config dsc = ma_data_source_config_init();
    dsc.vtable = &g_sp_vtable;
    if(ma_data_source_init(&dsc, (ma_data_source*)&sp->ds.base) != MA_SUCCESS) {
        ma_pcm_rb_uninit(&sp->rb);
        return 0;
    }

    if(ma_sound_init_from_data_source(engine,
                                      (ma_data_source*)&sp->ds.base,
                                      MA_SOUND_FLAG_NO_PITCH | MA_SOUND_FLAG_NO_SPATIALIZATION,
                                      NULL,
                                      &sp->sound) != MA_SUCCESS) {
        ma_data_source_uninit((ma_data_source*)&sp->ds.base);
        ma_pcm_rb_uninit(&sp->rb);
        return 0;
    }
    ma_sound_set_volume(&sp->sound, sp->volume);

    CodecConfig ccfg = {
        .sample_rate     = sp->sampleRate,
        .channels        = sp->channels,
        .bits_per_sample = 32
    };
    if(codec_runtime_init(&sp->codecRT, CODEC_ID_PCM, &ccfg)) {
        sp->codecInitialized = 1;
    }

    sp->initialized = 1;  // Mark as initialized
    return 1;
}

int stream_player_init_with_engine(StreamPlayer* self,
                                   void* engineWrapper,
                                   const StreamPlayerConfig* cfg)
{
    if (self == NULL || engineWrapper == NULL || cfg == NULL) return 0;
    
    // Cast void* back to Engine* (your wrapper type)
    Engine* engine = (Engine*)engineWrapper;
    ma_engine* mae = engine_get_ma_engine(engine);
    if (mae == NULL) return 0;
    
    // Forward to the standard initializer with individual parameters
    return stream_player_init(self, mae, cfg);
}

void stream_player_uninit(StreamPlayer* sp) {
    if(!sp || !sp->initialized) return;  // Use initialization flag instead of static guard
    
    if(sp->started) {
        ma_sound_stop(&sp->sound);
        sp->started = 0;
    }
    if(sp->codecInitialized) {
        codec_runtime_uninit(&sp->codecRT);
        sp->codecInitialized = 0;
    }
    ma_sound_uninit(&sp->sound);
    ma_data_source_uninit((ma_data_source*)&sp->ds.base);
    ma_pcm_rb_uninit(&sp->rb);
    
    sp->initialized = 0;  // Mark as uninitialized
}

/* Called by codec runtime to deliver decoded PCM. */
int codec_runtime_on_decoded_frames(CodecRuntime* rt,
                                    const float* pcm,
                                    int frames,
                                    void* userData)
{
    (void)rt;
    StreamPlayer* sp = (StreamPlayer*)userData;
    if(!sp || frames <= 0 || !pcm) return 0;

    int remaining = frames;
    int offsetFrames = 0;
    while(remaining > 0) {
        ma_uint32 space = ma_pcm_rb_available_write(&sp->rb);
        if(space == 0) {
            /* Drop oldest half to make space */
            ma_uint32 availRead = ma_pcm_rb_available_read(&sp->rb);
            if(availRead == 0) return 0; /* nothing to drop */
            ma_pcm_rb_seek_read(&sp->rb, availRead / 2);
            continue;
        }
        ma_uint32 writeNow = (ma_uint32)((remaining < (int)space) ? remaining : (int)space);
        void* pWrite = NULL;
        if(ma_pcm_rb_acquire_write(&sp->rb, &writeNow, &pWrite) != MA_SUCCESS || writeNow==0) break;
        memcpy(pWrite,
               pcm + offsetFrames * sp->channels,
               (size_t)writeNow * sp->channels * sizeof(float));
        ma_pcm_rb_commit_write(&sp->rb, writeNow);
        remaining     -= (int)writeNow;
        offsetFrames  += (int)writeNow;
    }
    return frames;
}

int stream_player_start(StreamPlayer* sp) {
    if(!sp) return 0;
    if(sp->started) return 1;
    if(ma_sound_start(&sp->sound) != MA_SUCCESS) return 0;
    sp->started = 1;
    return 1;
}

int stream_player_stop(StreamPlayer* sp) {
    if(!sp) return 0;
    if(!sp->started) return 1;
    ma_sound_stop(&sp->sound);
    sp->started = 0;
    return 1;
}

void stream_player_clear(StreamPlayer* sp) {
    if(!sp) return;
    ma_pcm_rb_reset(&sp->rb);
}

void stream_player_set_volume(StreamPlayer* sp, float volume) {
    if(!sp) return;
    sp->volume = volume;
    ma_sound_set_volume(&sp->sound, volume);
}

float stream_player_get_volume(StreamPlayer* sp) {
    return sp ? sp->volume : 1.0f;
}

size_t stream_player_write_frames_f32(StreamPlayer* sp,
                                      const float* frames,
                                      size_t frameCount)
{
    if(!sp || !frames || frameCount==0) return 0;
    size_t written = 0;
    while(written < frameCount) {
        ma_uint32 space = ma_pcm_rb_available_write(&sp->rb);
        if(space == 0) break;
        ma_uint32 req = (ma_uint32)((frameCount - written) < space ?
                                     (frameCount - written) : space);
        void* pWrite = NULL;
        if(ma_pcm_rb_acquire_write(&sp->rb, &req, &pWrite) != MA_SUCCESS || req==0) break;
        memcpy(pWrite,
               frames + written * sp->channels,
               (size_t)req * sp->channels * sizeof(float));
        ma_pcm_rb_commit_write(&sp->rb, req);
        written += req;
    }
    return written;
}

int stream_player_push_encoded_packet(StreamPlayer* sp,
                                      const void* packet,
                                      int packetBytes)
{
    if(!sp || !packet || packetBytes <= CODEC_FRAME_HEADER_BYTES) return 0;
    if(!sp->allowCodecPackets) return 0;

    const uint8_t* pkt = (const uint8_t*)packet;
    CodecID cid = (CodecID)pkt[0];

    if(!sp->codecInitialized || codec_runtime_current_id(&sp->codecRT) != cid) {
        if(sp->codecInitialized) {
            codec_runtime_uninit(&sp->codecRT);
            sp->codecInitialized = 0;
        }
        CodecConfig ccfg = {
            .sample_rate     = sp->sampleRate,
            .channels        = sp->channels,
            .bits_per_sample = 32
        };
        if(!codec_runtime_init(&sp->codecRT, cid, &ccfg)) return 0;
        sp->codecInitialized = 1;
    }

    return codec_runtime_push_packet(&sp->codecRT, pkt, packetBytes, sp);
}