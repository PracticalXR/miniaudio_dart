#ifndef CODEC_RUNTIME_H
#define CODEC_RUNTIME_H

#if __has_include("../external/miniaudio/include/miniaudio.h")
#include "../external/miniaudio/include/miniaudio.h"
#elif __has_include("miniaudio.h")
#include "miniaudio.h"
#else
#error "miniaudio.h not found for codec_runtime"
#endif

#include "codec.h"   /* for Codec / CodecID */

#ifdef __cplusplus
extern "C" {
#endif

/* Forward declare to avoid include cycle */
struct StreamPlayer;
typedef struct StreamPlayer StreamPlayer;

typedef struct CodecRuntime {
    Codec*     current;
    CodecConfig cfg;
    ma_mutex   lock;
} CodecRuntime;

int  codec_runtime_init(CodecRuntime* rt, CodecID initialID, const CodecConfig* cfg);
void codec_runtime_uninit(CodecRuntime* rt);
int  codec_runtime_push_packet(CodecRuntime* rt, const uint8_t* packet, int len, StreamPlayer* player);

#ifdef __cplusplus
}
#endif
#endif