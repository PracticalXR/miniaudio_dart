#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <threads.h>
#include "../include/codec.h"
#include "../include/codec_inline_encoder.h"

#ifdef HAVE_OPUS
extern Codec* codec_create_opus(const CodecConfig*, int application);
#endif

typedef struct {
    InlineEncoder* ie;
    int running;
} FeedCtx;

static int feeder_thread(void* arg){
    FeedCtx* fc=(FeedCtx*)arg;
    float* tmp = (float*)malloc(sizeof(float)* 960 * 4); /* up to 4 frames worth */
    while(fc->running){
        int mult = (rand()%4)+1;            /* 1..4 frames */
        int sz = 960 * mult;                /* 48k mono */
        for(int i=0;i<sz;i++) tmp[i] = (float)sin((double)i*0.01);
        inline_encoder_on_capture(fc->ie, tmp, sz);
        thrd_sleep(&(struct timespec){.tv_nsec= (long)( (rand()%4000+1000) *1000 )}, NULL);
    }
    free(tmp);
    return 0;
}

int main(void){
#ifndef HAVE_OPUS
    printf("HAVE_OPUS not enabled.\n");
    return 0;
#else
    srand((unsigned)time(NULL));
    CodecConfig cfg;
    cfg.sample_rate=48000;
    cfg.channels=1;
    cfg.bits_per_sample=32;

    Codec* c = codec_create_opus(&cfg, 2049);
    if(!c){
        fprintf(stderr,"Failed to create Opus codec\n");
        return 1;
    }
    InlineEncoder ie;
    if(!inline_encoder_init(&ie, c, 1, 32, 256)){
        fprintf(stderr,"inline_encoder_init failed\n");
        return 1;
    }

    FeedCtx fc; fc.ie=&ie; fc.running=1;
    thrd_t t1,t2;
    thrd_create(&t1, feeder_thread, &fc);
    thrd_create(&t2, feeder_thread, &fc);

    const time_t start=time(NULL);
    while(time(NULL)-start < 10){
        uint8_t buf[2000];
        int popped = inline_encoder_dequeue(&ie, buf, sizeof(buf));
        (void)popped;
        thrd_sleep(&(struct timespec){.tv_nsec=5*1000*1000}, NULL);
    }
    fc.running=0;
    thrd_join(t1,NULL);
    thrd_join(t2,NULL);
    inline_encoder_uninit(&ie);
    printf("Stress test finished (no crash)\n");
    return 0;
#endif
}