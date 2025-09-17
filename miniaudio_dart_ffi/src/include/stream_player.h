#ifndef STREAM_PLAYER_H
#define STREAM_PLAYER_H

#include <stddef.h>
#include <stdint.h>
#include "../external/miniaudio/include/miniaudio.h"
#include "export.h"
#include "engine.h"
#include "codec_runtime.h"   /* add for decoder */

// Forward decls already present
typedef struct StreamPlayer StreamPlayer;

/* Push a framed encoded packet: [codec_id][flags][seq16][len16][payload...] */
EXPORT int stream_player_push_encoded_packet(StreamPlayer* sp,
                                             const void* data,
                                             int len);

EXPORT StreamPlayer* stream_player_alloc();
EXPORT void          stream_player_free(StreamPlayer* self);
EXPORT int  stream_player_init(StreamPlayer* self,
                               ma_engine* engine,
                               ma_format format, int channels, int sample_rate,
                               uint32_t buffer_ms);
// Convenience: init using Engine* (no need to expose ma_engine* to Dart)
EXPORT int  stream_player_init_with_engine(StreamPlayer* self,
                                           Engine* engine,
                                           ma_format format, int channels, int sample_rate,
                                           uint32_t buffer_ms);
EXPORT void stream_player_uninit(StreamPlayer* self);

EXPORT int  stream_player_start(StreamPlayer* self);
EXPORT int  stream_player_stop(StreamPlayer* self);
EXPORT void stream_player_clear(StreamPlayer* self);
EXPORT void stream_player_set_volume(StreamPlayer* self, float volume);

// Write interleaved f32. Returns frames written.
EXPORT size_t stream_player_write_frames_f32(StreamPlayer* self,
                                             const float* interleaved,
                                             size_t frames);
#endif