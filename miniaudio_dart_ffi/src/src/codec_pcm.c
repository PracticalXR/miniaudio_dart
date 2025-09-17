#include "../include/codec.h"
#include <stdlib.h>
#include <string.h>

typedef struct {
    int frame_size;
    int bytes_per_frame;
    int uses_float;
} PCMState;

static void pcm_destroy(Codec* c) {
    if (!c) return;
    free(c->impl);
    free(c);
}

static int pcm_encode(Codec* c, const void* pcmFrames, int frameCount,
                      uint8_t* outBuf, int outCap) {
    PCMState* s = (PCMState*)c->impl;
    int need = frameCount * s->bytes_per_frame;
    if (need > outCap) return -1;
    memcpy(outBuf, pcmFrames, (size_t)need);
    return need;
}

static int pcm_decode(Codec* c, const uint8_t* packet, int packetLen,
                      void* pcmOut, int maxFrames) {
    PCMState* s = (PCMState*)c->impl;
    int frames = packetLen / s->bytes_per_frame;
    if (frames > maxFrames) return -1;
    memcpy(pcmOut, packet, (size_t)packetLen);
    return frames;
}

Codec* codec_create_null_passthrough(const CodecConfig* cfg) {
    if (!cfg || cfg->channels <= 0) return NULL;
    Codec* c = (Codec*)calloc(1, sizeof(Codec));
    PCMState* st = (PCMState*)calloc(1, sizeof(PCMState));
    if (!c || !st) { free(c); free(st); return NULL; }

    st->uses_float = (cfg->bits_per_sample == 32);
    st->bytes_per_frame = (cfg->bits_per_sample / 8) * cfg->channels;
    st->frame_size = 960;

    c->impl = st;
    c->vt.id = CODEC_ID_PCM;
    c->vt.destroy = pcm_destroy;
    c->vt.encode = pcm_encode;
    c->vt.decode = pcm_decode;
    c->vt.frame_size = st->frame_size;
    c->vt.uses_float = st->uses_float;
    c->vtableVersion = CODEC_VTABLE_VERSION; /* add */
    return c;
}