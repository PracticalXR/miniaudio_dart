#ifndef STREAM_PLAYER_H
#define STREAM_PLAYER_H

#include <stddef.h>
#include <stdint.h>
#if __has_include("../external/miniaudio/include/miniaudio.h")
#include "../external/miniaudio/include/miniaudio.h"
#elif __has_include("miniaudio.h")
#include "miniaudio.h"
#else
#error "miniaudio.h not found"
#endif
#include "codec.h"
#include "codec_runtime.h"
#include "codec_packet_format.h"
#include "export.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct StreamPlayer StreamPlayer;

typedef struct StreamPlayerConfig {
    ma_format format;
    int       channels;
    int       sampleRate;
    uint32_t  bufferMilliseconds;
    int       allowCodecPackets;
    int       decodeAccumFrames; /* reserved */
} StreamPlayerConfig;

EXPORT StreamPlayerConfig stream_player_config_default(int channels, int sampleRate);

EXPORT StreamPlayer* stream_player_alloc(void);
EXPORT void          stream_player_free(StreamPlayer* sp);

EXPORT int  stream_player_init(StreamPlayer* sp,
                               ma_engine* engine,
                               const StreamPlayerConfig* cfg);

EXPORT int  stream_player_init_with_engine(StreamPlayer* sp,
                                           void* engineWrapper,
                                           const StreamPlayerConfig* cfg);

EXPORT void stream_player_uninit(StreamPlayer* sp);
EXPORT int  stream_player_start(StreamPlayer* sp);
EXPORT int  stream_player_stop(StreamPlayer* sp);
EXPORT void stream_player_clear(StreamPlayer* sp);
EXPORT void  stream_player_set_volume(StreamPlayer* sp, float volume);
EXPORT float stream_player_get_volume(StreamPlayer* sp);

EXPORT size_t stream_player_write_frames_f32(StreamPlayer* sp,
                                             const float* frames,
                                             size_t frameCount);

EXPORT int stream_player_push_encoded_packet(StreamPlayer* sp,
                                             const void* packet,
                                             int packetBytes);

/* Called by codec runtime to deliver decoded PCM. */
EXPORT int codec_runtime_on_decoded_frames(CodecRuntime* rt,
                                           const float* pcm,
                                           int frames,
                                           void* userData);

#ifdef __cplusplus
}
#endif
#endif /* STREAM_PLAYER_H */