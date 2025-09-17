// filepath: d:\Code\git\practical\miniaudio_dart\miniaudio_dart_ffi\src\include\codec_packet_queue.h
#ifndef CODEC_PACKET_QUEUE_H
#define CODEC_PACKET_QUEUE_H
#include <stdint.h>
#ifndef CODEC_MAX_PACKET_BYTES
#define CODEC_MAX_PACKET_BYTES 2048
#endif
typedef struct {
    uint16_t len;
    uint8_t  data[CODEC_MAX_PACKET_BYTES];
} CodecPacket;
typedef struct {
    CodecPacket* packets;
    uint32_t capacity, readIndex, writeIndex, count;
} CodecPacketQueue;
int  codec_packet_queue_init(CodecPacketQueue* q, uint32_t capacity);
void codec_packet_queue_uninit(CodecPacketQueue* q);
int  codec_packet_queue_push(CodecPacketQueue* q, const uint8_t* data, uint16_t len);
int  codec_packet_queue_pop(CodecPacketQueue* q, uint8_t* out, uint16_t cap);
uint32_t codec_packet_queue_count(const CodecPacketQueue* q);
#endif