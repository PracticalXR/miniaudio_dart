#include "../include/codec_packet_queue.h"
#include <stdlib.h>
#include <string.h>

int codec_packet_queue_init(CodecPacketQueue* q, uint32_t cap){
    if(!q||!cap)return 0;
    q->packets=(CodecPacket*)calloc(cap,sizeof(CodecPacket));
    if(!q->packets)return 0;
    q->capacity=cap;
    return 1;
}

void codec_packet_queue_uninit(CodecPacketQueue* q){
    if(!q)return;
    free(q->packets);
    memset(q,0,sizeof(*q));
}

int codec_packet_queue_push(CodecPacketQueue* q,const uint8_t* d,uint16_t len){
    if(!q||!d||!len)return 0;
    if(len>CODEC_MAX_PACKET_BYTES)return 0;
    if(q->count==q->capacity)return 0;
    CodecPacket* slot=&q->packets[q->writeIndex];
    slot->len=len;
    memcpy(slot->data,d,len);
    q->writeIndex=(q->writeIndex+1)%q->capacity;
    q->count++;
    return 1;
}

int codec_packet_queue_pop(CodecPacketQueue* q,uint8_t* out,uint16_t cap){
    if(!q||!out)return 0;
    if(q->count==0)return 0;
    CodecPacket* slot=&q->packets[q->readIndex];
    if(slot->len>cap)return -1;
    memcpy(out,slot->data,slot->len);
    int w=slot->len;
    q->readIndex=(q->readIndex+1)%q->capacity;
    q->count--;
    return w;
}

uint32_t codec_packet_queue_count(const CodecPacketQueue* q){ return q?q->count:0; }

/* Wrappers */
int  cpq_init(CodecPacketQueue* q, uint32_t c)               { return codec_packet_queue_init(q,c); }
void cpq_uninit(CodecPacketQueue* q)                         { codec_packet_queue_uninit(q); }
int  cpq_push(CodecPacketQueue* q, const uint8_t* d, uint16_t l){ return codec_packet_queue_push(q,d,l); }
int  cpq_pop(CodecPacketQueue* q, uint8_t* o, uint16_t cap)  { return codec_packet_queue_pop(q,o,cap); }
uint32_t cpq_count(const CodecPacketQueue* q)                { return codec_packet_queue_count(q); }