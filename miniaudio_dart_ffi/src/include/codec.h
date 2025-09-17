#ifndef MA_CODEC_ABI_H
#define MA_CODEC_ABI_H
#include <stdint.h>

#define CODEC_VTABLE_VERSION 1

typedef enum {
    CODEC_ID_NONE = 0,
    CODEC_ID_OPUS = 1,
    CODEC_ID_PCM  = 2
} CodecID;

typedef struct {
    int sample_rate;
    int channels;
    int bits_per_sample; /* 16 or 32 */
} CodecConfig;

typedef struct Codec Codec;

typedef struct {
    CodecID id;
    void (*destroy)(Codec*);
    int (*encode)(Codec*, const void* pcmFrames, int frameCount, uint8_t* outBuf, int outCap);
    int (*decode)(Codec*, const uint8_t* packet, int packetLen, void* pcmOut, int maxFrames);
    int frame_size;
    int uses_float;
} CodecVTable;

struct Codec {
    CodecVTable vt;
    void* impl;
    uint32_t vtableVersion;
};

/* Factories */
Codec* codec_create_opus(const CodecConfig* cfg, int application);
Codec* codec_create_null_passthrough(const CodecConfig* cfg);

#endif