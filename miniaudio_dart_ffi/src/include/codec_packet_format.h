#ifndef CODEC_PACKET_FORMAT_H
#define CODEC_PACKET_FORMAT_H
/* Header (6 bytes):
   0: codec id
   1: flags (unused=0)
   2-3: seq (LE)
   4-5: payload length (LE)
*/
#define CODEC_FRAME_HEADER_BYTES 6
#endif