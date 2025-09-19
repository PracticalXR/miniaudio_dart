#ifndef CROSSCODER_H
#define CROSSCODER_H

#include <stdint.h>
#if __has_include("../external/miniaudio/include/miniaudio.h")
#include "../external/miniaudio/include/miniaudio.h"
#elif __has_include("miniaudio.h")
#include "miniaudio.h"
#else
#error "miniaudio.h not found"
#endif
#include "codec.h"
#include "codec_packet_format.h"
#include "export.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CrossCoder {
    Codec*   codec;
    int      channels;
    int      frameSize;      /* codec frame size (PCM frames) */
    int      usesFloat;
    int      accumulate;     /* 1 = allow partial feeds */
    float*   accum;
    int      accumFrames;
    ma_mutex lock;
    int      disposed;
    
    /* Runtime configuration storage */
    int      bitrate;
    int      complexity;
    int      vbr;
    int      application;
    CodecID  codecId;
    CodecConfig config;
    
#if INLINE_ENCODER_DEBUG
    uint32_t dbg_canary_head;
    uint32_t dbg_canary_tail;
#endif
} CrossCoder;

EXPORT CrossCoder* crosscoder_create(const CodecConfig* cfg,
                                     CodecID codecID,
                                     int application,
                                     int accumulate);

EXPORT void        crosscoder_destroy(CrossCoder* cc);
EXPORT int         crosscoder_frame_size(CrossCoder* cc);

EXPORT int crosscoder_encode_push_f32(CrossCoder* cc,
                                      const float* frames,
                                      int frameCount,
                                      uint8_t* outPacket,
                                      int outCap,
                                      int* outBytes);

EXPORT int crosscoder_encode_flush(CrossCoder* cc,
                                   int pad,
                                   uint8_t* outPacket,
                                   int outCap,
                                   int* outBytes);

EXPORT int crosscoder_decode_packet(CrossCoder* cc,
                                    const uint8_t* packet,
                                    int packetLen,
                                    float* outFrames,
                                    int maxFrames);

/* Runtime configuration functions */
EXPORT int crosscoder_set_bitrate(CrossCoder* cc, int bitrate);
EXPORT int crosscoder_set_complexity(CrossCoder* cc, int complexity);
EXPORT int crosscoder_set_vbr(CrossCoder* cc, int vbr);
EXPORT int crosscoder_get_bitrate(CrossCoder* cc);
EXPORT int crosscoder_get_complexity(CrossCoder* cc);
EXPORT int crosscoder_get_vbr(CrossCoder* cc);

#ifdef __cplusplus
}
#endif
#endif /* CROSSCODER_H */