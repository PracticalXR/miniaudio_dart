// filepath: d:\Code\git\practical\miniaudio_dart\miniaudio_dart_ffi\src\include\codec_inline_encoder.h
#ifndef CODEC_INLINE_ENCODER_H
#define CODEC_INLINE_ENCODER_H
#include <stdint.h>
#include "codec.h"
#include "codec_packet_queue.h"
#include "../external/miniaudio/include/miniaudio.h"

typedef struct InlineEncoder {
    Codec*           codec;
    CodecPacketQueue queue;
    int              channels;
    float*           accum;
    int              accumFrames;
    int              frameSize;
    ma_mutex         lock;
} InlineEncoder;

int  inline_encoder_init(InlineEncoder* ie, Codec* codec, int channels, int bits_per_sample, uint32_t queueCap);
void inline_encoder_uninit(InlineEncoder* ie);
void inline_encoder_on_capture(InlineEncoder* ie, const float* frames, int frameCount);
int  inline_encoder_flush(InlineEncoder* ie, int padWithZeros);
int  inline_encoder_dequeue(InlineEncoder* ie, uint8_t* out, uint16_t cap);
uint32_t inline_encoder_pending(InlineEncoder* ie);

#endif