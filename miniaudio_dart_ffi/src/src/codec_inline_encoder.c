#include "../include/codec_inline_encoder.h"
#include "../include/codec_packet_format.h"
#include <stdio.h>  // add for debug
#include <stdlib.h>
#include <string.h>

#define HDR 6
static uint16_t g_seq = 0;

int inline_encoder_init(InlineEncoder* ie, Codec* codec, int channels, int bits_per_sample, uint32_t queueCap) {
    (void)bits_per_sample;
    if(!ie||!codec||channels<=0)return 0;
    memset(ie,0,sizeof(*ie));
    ie->codec=codec;
    ie->channels=channels;
    ie->frameSize=codec->vt.frame_size;
    if(ie->frameSize<=0)return 0;
    if(!codec_packet_queue_init(&ie->queue, queueCap?queueCap:128))return 0;
    ie->accum=(float*)malloc(sizeof(float)*ie->frameSize*channels);
    if(!ie->accum){ codec_packet_queue_uninit(&ie->queue); return 0; }
    ma_mutex_init(&ie->lock);
    return 1;
}

void inline_encoder_uninit(InlineEncoder* ie){
    if(!ie)return;
    free(ie->accum);
    codec_packet_queue_uninit(&ie->queue);
    ma_mutex_uninit(&ie->lock);
    memset(ie,0,sizeof(*ie));
}

static void encode_full(InlineEncoder* ie){
    uint8_t pkt[CODEC_MAX_PACKET_BYTES];
    int payloadCap=(int)sizeof(pkt)-CODEC_FRAME_HEADER_BYTES;
    int encoded=ie->codec->vt.encode(ie->codec, ie->accum, ie->frameSize, pkt+CODEC_FRAME_HEADER_BYTES, payloadCap);
    if(encoded<=0 || encoded+CODEC_FRAME_HEADER_BYTES > (int)sizeof(pkt)) return;
    pkt[0]=(uint8_t)ie->codec->vt.id;
    pkt[1]=0;
    uint16_t seq=g_seq++;
    uint16_t plen=(uint16_t)encoded;
    memcpy(pkt+2,&seq,2);
    memcpy(pkt+4,&plen,2);
    // DEBUG
    // fprintf(stderr,"[enc] seq=%u plen=%u total=%u\n", (unsigned)seq, (unsigned)plen, (unsigned)(plen+CODEC_FRAME_HEADER_BYTES));
    codec_packet_queue_push(&ie->queue, pkt, (uint16_t)(encoded+CODEC_FRAME_HEADER_BYTES));
}

void inline_encoder_on_capture(InlineEncoder* ie, const float* frames, int frameCount){
    if(!ie||!frames||frameCount<=0)return;
    ma_mutex_lock(&ie->lock);
    int ch=ie->channels;
    int fs=ie->frameSize;
    int copied=0;
    while(copied<frameCount){
        int need=fs - ie->accumFrames;
        int avail=frameCount - copied;
        int take=avail<need?avail:need;
        memcpy(ie->accum + ie->accumFrames*ch,
               frames + copied*ch,
               (size_t)take*ch*sizeof(float));
        ie->accumFrames+=take;
        copied+=take;
        if(ie->accumFrames==fs){
            encode_full(ie);
            ie->accumFrames=0;
        }
    }
    ma_mutex_unlock(&ie->lock);
}

int inline_encoder_flush(InlineEncoder* ie, int padWithZeros){
    if(!ie)return 0;
    ma_mutex_lock(&ie->lock);
    if(ie->accumFrames>0){
        int ch=ie->channels;
        int fs=ie->frameSize;
        if(padWithZeros){
            int remain=fs - ie->accumFrames;
            memset(ie->accum + ie->accumFrames*ch, 0, (size_t)remain*ch*sizeof(float));
            ie->accumFrames=fs;
        }
        if(ie->accumFrames==fs){
            encode_full(ie);
            ie->accumFrames=0;
            ma_mutex_unlock(&ie->lock);
            return 1;
        }
    }
    ma_mutex_unlock(&ie->lock);
    return 0;
}

int inline_encoder_dequeue(InlineEncoder* ie, uint8_t* out, uint16_t cap){
    if(!ie)return 0;
    return codec_packet_queue_pop(&ie->queue, out, cap);
}
uint32_t inline_encoder_pending(InlineEncoder* ie){
    return ie?codec_packet_queue_count(&ie->queue):0;
}