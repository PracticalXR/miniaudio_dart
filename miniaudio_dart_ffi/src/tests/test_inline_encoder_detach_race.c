#include <stdio.h>
#include <stdlib.h>
#include <threads.h>
#include <time.h>
#include "../include/codec.h"
#include "../include/codec_inline_encoder.h"

#ifdef HAVE_OPUS
extern Codec* codec_create_opus(const CodecConfig*, int application);
#endif

static int feed_func(void* arg){
    InlineEncoder* ie=(InlineEncoder*)arg;
    float frame[960];
    while(1){
        for(int i=0;i<960;i++) frame[i]=(float)i/960.0f;
        inline_encoder_on_capture(ie, frame, 960);
    }
    return 0;
}

int main(void){
#ifndef HAVE_OPUS
    return 0;
#else
    CodecConfig cfg={48000,1,32};
    Codec* c = codec_create_opus(&cfg, 2049);
    InlineEncoder* ie = (InlineEncoder*)malloc(sizeof(InlineEncoder));
    inline_encoder_init(ie,c,1,32,64);
    thrd_t feeder;
    thrd_create(&feeder, feed_func, ie);
    thrd_sleep(&(struct timespec){.tv_sec=0,.tv_nsec=200*1000*1000}, NULL);
    // Race detach
    inline_encoder_uninit(ie);
    free(ie);
    printf("Detach race complete (if ASAN ok -> pass)\n");
    return 0;
#endif
}