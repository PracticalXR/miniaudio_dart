#ifdef HAVE_OPUS
# if __has_include(<opus/opus.h>)
#  include <opus/opus.h>
# elif __has_include(<opus.h>)
#  include <opus.h>
# else
#  error "Opus headers not found"
# endif
#include "../include/codec.h"
#include <stdlib.h>

static const char* g_opus_last_err = NULL;
const char* codec_opus_last_error(void){ return g_opus_last_err ? g_opus_last_err : "ok"; }

typedef struct {
    OpusEncoder* enc;
    OpusDecoder* dec;
    int frame_size;
    int channels;
    int sample_rate;
} OpusPair;

static void opus_destroy(Codec* c){
    if(!c) return;
    OpusPair* p=(OpusPair*)c->impl;
    if(p){
        if(p->enc) opus_encoder_destroy(p->enc);
        if(p->dec) opus_decoder_destroy(p->dec);
        free(p);
    }
    free(c);
}

static int opus_encode_wrap(Codec* c,const void* pcmFrames,int frameCount,uint8_t* out,int cap){
    OpusPair* p=(OpusPair*)c->impl;
    if(!p||frameCount!=p->frame_size) return -1;
    return opus_encode_float(p->enc,(const float*)pcmFrames,frameCount,out,cap);
}

static int opus_decode_wrap(Codec* c,const uint8_t* packet,int packetLen,void* pcmOut,int maxFrames){
    OpusPair* p=(OpusPair*)c->impl;
    if(!p)return -1;
    return opus_decode_float(p->dec,packet,packetLen,(float*)pcmOut,maxFrames,0);
}

/* Accept common sample rates (48k, 24k, 16k, 12k, 8k). Frame size = 20 ms. */
static int calc_frame_size(int sr){
    switch(sr){
        case 48000: return 960;
        case 24000: return 480;
        case 16000: return 320;
        case 12000: return 240;
        case  8000: return 160;
        default: return 0;
    }
}

Codec* codec_create_opus(const CodecConfig* cfg, int application){
    g_opus_last_err = NULL;
    if(!cfg){ g_opus_last_err="null cfg"; return NULL; }
    int fs = calc_frame_size(cfg->sample_rate);
    if(fs==0){ g_opus_last_err="unsupported sample_rate"; return NULL; }
    if(cfg->channels<=0 || cfg->channels>2){ g_opus_last_err="bad channels"; return NULL; }

    int err;
    Codec* c = (Codec*)calloc(1,sizeof(Codec));
    OpusPair* p = (OpusPair*)calloc(1,sizeof(OpusPair));
    if(!c||!p){ free(c); free(p); g_opus_last_err="alloc fail"; return NULL; }

    p->channels = cfg->channels;
    p->frame_size = fs;
    p->sample_rate = cfg->sample_rate;

    p->enc = opus_encoder_create(cfg->sample_rate, cfg->channels, application, &err);
    if(err!=OPUS_OK){ g_opus_last_err="enc create"; opus_destroy(c); return NULL; }
    p->dec = opus_decoder_create(cfg->sample_rate, cfg->channels, &err);
    if(err!=OPUS_OK){ g_opus_last_err="dec create"; opus_destroy(c); return NULL; }

    c->impl = p;
    c->vt.id = CODEC_ID_OPUS;
    c->vt.destroy = opus_destroy;
    c->vt.encode = opus_encode_wrap;
    c->vt.decode = opus_decode_wrap;
    c->vt.frame_size = p->frame_size;
    c->vt.uses_float = 1;
    c->vtableVersion = CODEC_VTABLE_VERSION;
    return c;
}
#endif