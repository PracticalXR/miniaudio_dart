#include "../include/codec_runtime.h"
#include "../include/codec.h"
#include "../include/stream_player.h"
#include "../include/codec_packet_format.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef HAVE_OPUS
# if __has_include(<opus/opus.h>)
#  include <opus/opus.h>
# elif __has_include(<opus.h>)
#  include <opus.h>
# else
#  error "Opus headers not found"
# endif
#endif

/* Use real factory signatures from codec.h */
static Codec* make_codec(CodecID id, const CodecConfig* cfg) {
    if (!cfg) return NULL;
#ifdef HAVE_OPUS
    if (id == CODEC_ID_OPUS) {
        return codec_create_opus(cfg, OPUS_APPLICATION_AUDIO);
    }
#endif
    if (id == CODEC_ID_PCM) {
        return codec_create_null_passthrough(cfg);
    }
    return NULL;
}

int codec_runtime_init(CodecRuntime* rt, CodecID initialID, const CodecConfig* cfg) {
    if (!rt || !cfg) return 0;
    memset(rt, 0, sizeof(*rt));
    rt->cfg = *cfg;
    if (ma_mutex_init(&rt->lock) != MA_SUCCESS) return 0;
    /* Lazy: only create if a concrete initial codec requested */
    if (initialID != CODEC_ID_NONE)
        rt->current = make_codec(initialID, &rt->cfg);
    return 1;
}

void codec_runtime_uninit(CodecRuntime* rt) {
    if (!rt) return;
    ma_mutex_lock(&rt->lock);
    if (rt->current && rt->current->vt.destroy) {
        rt->current->vt.destroy(rt->current);
    }
    rt->current = NULL;
    ma_mutex_unlock(&rt->lock);
    ma_mutex_uninit(&rt->lock);
}

int codec_runtime_push_packet(CodecRuntime* rt, const uint8_t* packet, int len,
                              StreamPlayer* player) {
    if (!rt || !packet || len < CODEC_FRAME_HEADER_BYTES) return 0;

    CodecID cid = (CodecID)packet[0];
    uint16_t plen;
    memcpy(&plen, packet + 4, 2);
    if ((int)(plen + CODEC_FRAME_HEADER_BYTES) != len) {
        return 0;
    }

    /* Ensure correct codec */
    ma_mutex_lock(&rt->lock);
    if (!rt->current || rt->current->vt.id != cid) {
        if (rt->current && rt->current->vt.destroy)
            rt->current->vt.destroy(rt->current);
        rt->current = make_codec(cid, &rt->cfg);
    }
    Codec* c = rt->current;
    ma_mutex_unlock(&rt->lock);
    if (!c) return 0;

    float decodeBuf[5760 * 2]; /* 120 ms @48k stereo max */
    const int maxFrames = 5760;
    int frames = c->vt.decode(c,
                              packet + CODEC_FRAME_HEADER_BYTES,
                              plen,
                              decodeBuf,
                              maxFrames);
    if (frames <= 0) return 0;
    if (frames > maxFrames) frames = maxFrames;
    stream_player_write_frames_f32(player, decodeBuf, (size_t)frames);
    return frames;
}