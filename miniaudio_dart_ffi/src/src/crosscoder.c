#include "../include/crosscoder.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// PCM passthrough codec implementation
static int pcm_encode(Codec* c, const float* frames, int frameCount, 
                      uint8_t* outBuf, int outCap) {
    if (!c || !frames || !outBuf || frameCount <= 0) return 0;
    
    // For PCM, we need to know channels - get from CrossCoder context
    // Since we can't store config in Codec, we'll assume mono for simplicity
    // or get channels from the CrossCoder that owns this codec
    int channels = 1; // Default to mono for PCM passthrough
    int bytesNeeded = frameCount * channels * sizeof(float);
    
    if (bytesNeeded > outCap) return 0;
    
    memcpy(outBuf, frames, bytesNeeded);
    return bytesNeeded;
}

static int pcm_decode(Codec* c, const uint8_t* packet, int packetLen,
                      float* outFrames, int maxFrames) {
    if (!c || !packet || !outFrames || packetLen <= 0) return 0;
    
    // For PCM, packet is just raw float data
    int channels = 1; // Default to mono
    int frameBytes = channels * sizeof(float);
    int availableFrames = packetLen / frameBytes;
    int framesToCopy = (availableFrames < maxFrames) ? availableFrames : maxFrames;
    
    if (framesToCopy > 0) {
        memcpy(outFrames, packet, framesToCopy * frameBytes);
    }
    return framesToCopy;
}

static void pcm_destroy(Codec* c) {
    if (c) free(c);
}

// PCM codec that works with actual channel info from CrossCoder
typedef struct {
    Codec base;
    int channels;
    int sampleRate;
} PCMCodec;

static int pcm_encode_with_channels(Codec* c, const float* frames, int frameCount, 
                                    uint8_t* outBuf, int outCap) {
    if (!c || !frames || !outBuf || frameCount <= 0) return 0;
    
    PCMCodec* pcm = (PCMCodec*)c;
    int bytesNeeded = frameCount * pcm->channels * sizeof(float);
    
    if (bytesNeeded > outCap) return 0;
    
    memcpy(outBuf, frames, bytesNeeded);
    return bytesNeeded;
}

static int pcm_decode_with_channels(Codec* c, const uint8_t* packet, int packetLen,
                                    float* outFrames, int maxFrames) {
    if (!c || !packet || !outFrames || packetLen <= 0) return 0;
    
    PCMCodec* pcm = (PCMCodec*)c;
    int frameBytes = pcm->channels * sizeof(float);
    int availableFrames = packetLen / frameBytes;
    int framesToCopy = (availableFrames < maxFrames) ? availableFrames : maxFrames;
    
    if (framesToCopy > 0) {
        memcpy(outFrames, packet, framesToCopy * frameBytes);
    }
    return framesToCopy;
}

static void pcm_destroy_extended(Codec* c) {
    if (c) free(c);
}

// Simpler approach - use CrossCoder's channel info
static int pcm_encode_simple(Codec* c, const void* frames, int frameCount, 
                             uint8_t* outBuf, int outCap) {
    if (!c || !frames || !outBuf || frameCount <= 0) return 0;
    
    // Cast void* to float* since we know PCM uses float
    const float* floatFrames = (const float*)frames;
    
    // frameCount is the number of samples (already includes channels)
    int bytesNeeded = frameCount * sizeof(float);
    
    if (bytesNeeded > outCap) return 0;
    
    memcpy(outBuf, floatFrames, bytesNeeded);
    return bytesNeeded;
}

static int pcm_decode_simple(Codec* c, const uint8_t* packet, int packetLen,
                             void* outFrames, int maxFrames) {
    if (!c || !packet || !outFrames || packetLen <= 0) return 0;
    
    // Cast void* to float* since we know PCM uses float
    float* floatFrames = (float*)outFrames;
    
    // Packet is raw float data, copy as much as fits
    int floatsAvailable = packetLen / sizeof(float);
    int floatsToCopy = (floatsAvailable < maxFrames) ? floatsAvailable : maxFrames;
    
    if (floatsToCopy > 0) {
        memcpy(floatFrames, packet, floatsToCopy * sizeof(float));
    }
    return floatsToCopy;
}

static Codec* cc_make_codec(CodecID id, const CodecConfig* cfg, int application) {
    if (!cfg) return NULL;
    
    switch (id) {
        case CODEC_ID_PCM: {
            Codec* c = (Codec*)calloc(1, sizeof(Codec));
            if (!c) return NULL;
            
            c->vt.id = CODEC_ID_PCM;
            c->vt.frame_size = 960; // 20ms at 48kHz  
            c->vt.uses_float = 1;
            c->vt.encode = pcm_encode_simple;  // Now matches void* signature
            c->vt.decode = pcm_decode_simple;  // Now matches void* signature
            c->vt.destroy = pcm_destroy;
            
            return c;
        }
        
        case CODEC_ID_OPUS: {
            return codec_create_opus(cfg, application);
        }
        
        default:
            return NULL;
    }
}

static void cc_dbg(CrossCoder* cc){
#if INLINE_ENCODER_DEBUG
    if(cc->dbg_canary_head!=0xA11ECAFEu || cc->dbg_canary_tail!=0xFEEDBEEFu){
        fprintf(stderr,"[crosscoder][FATAL] canary corrupt\n");
        abort();
    }
#endif
}

CrossCoder* crosscoder_create(const CodecConfig* cfg,
                              CodecID codecID,
                              int application,
                              int accumulate)
{
    if(!cfg) return NULL;
    Codec* c = cc_make_codec(codecID, cfg, application);
    if(!c) return NULL;

    CrossCoder* cc = (CrossCoder*)calloc(1,sizeof(CrossCoder));
    if(!cc){ if(c->vt.destroy) c->vt.destroy(c); return NULL; }

    cc->codec     = c;
    cc->channels  = cfg->channels;
    cc->frameSize = c->vt.frame_size;
    cc->usesFloat = c->vt.uses_float;
    cc->accumulate= accumulate ? 1 : 0;
    
    /* Store configuration for runtime changes */
    cc->codecId = codecID;
    cc->application = application;
    cc->config = *cfg;
    cc->bitrate = 64000;    /* Default Opus bitrate */
    cc->complexity = 5;     /* Default Opus complexity */
    cc->vbr = 1;           /* Default VBR enabled */
    
    if(cc->frameSize <= 0 || cc->channels <= 0){
        crosscoder_destroy(cc);
        return NULL;
    }
    if(accumulate){
        cc->accum = (float*)malloc(sizeof(float)*(size_t)cc->frameSize*(size_t)cc->channels);
        if(!cc->accum){ crosscoder_destroy(cc); return NULL; }
    }
    if(ma_mutex_init(&cc->lock)!=MA_SUCCESS){
        crosscoder_destroy(cc);
        return NULL;
    }
#if INLINE_ENCODER_DEBUG
    cc->dbg_canary_head=0xA11ECAFEu;
    cc->dbg_canary_tail=0xFEEDBEEFu;
#endif
    return cc;
}

void crosscoder_destroy(CrossCoder* cc){
    if(!cc) return;
    ma_mutex_lock(&cc->lock);
    cc->disposed=1;
    if(cc->codec && cc->codec->vt.destroy) cc->codec->vt.destroy(cc->codec);
    cc->codec=NULL;
    free(cc->accum);
    ma_mutex_unlock(&cc->lock);
    ma_mutex_uninit(&cc->lock);
    free(cc);
}

int crosscoder_frame_size(CrossCoder* cc){
    return cc ? cc->frameSize : 0;
}

static int cc_do_encode(CrossCoder* cc,
                        const float* frames,
                        uint8_t* outPacket,
                        int outCap)
{
    /* outPacket must have space for header + payload */
    uint8_t* payload = outPacket + CODEC_FRAME_HEADER_BYTES;
    int payloadCap   = outCap - CODEC_FRAME_HEADER_BYTES;
    if(payloadCap <= 0) return 0;

    int encoded = cc->codec->vt.encode(cc->codec,
                                       frames,
                                       cc->frameSize,
                                       payload,
                                       payloadCap);
    if(encoded <= 0) return 0;

    /* Header (codec ID, channels, frameSize, payload len) */
    outPacket[0] = (uint8_t)cc->codec->vt.id;
    outPacket[1] = (uint8_t)cc->channels;
    outPacket[2] = (uint8_t)(cc->frameSize & 0xFF);
    outPacket[3] = (uint8_t)((cc->frameSize>>8) & 0xFF);
    uint16_t plen = (uint16_t)encoded;
    memcpy(outPacket+4, &plen, 2);
    return encoded + CODEC_FRAME_HEADER_BYTES;
}

int crosscoder_encode_push_f32(CrossCoder* cc,
                               const float* frames,
                               int frameCount,
                               uint8_t* outPacket,
                               int outCap,
                               int* outBytes)
{
    if(outBytes) *outBytes = 0;
    if(!cc || !frames || frameCount <=0 || !cc->usesFloat) return 0;
    ma_mutex_lock(&cc->lock);
    if(cc->disposed){ ma_mutex_unlock(&cc->lock); return 0; }
    cc_dbg(cc);

    if(!cc->accumulate){
        if(frameCount != cc->frameSize){
            ma_mutex_unlock(&cc->lock);
            return 0; /* must match exactly */
        }
        int packetBytes = cc_do_encode(cc, frames, outPacket, outCap);
        if(outBytes) *outBytes = packetBytes;
        ma_mutex_unlock(&cc->lock);
        return frameCount;
    }

    /* Accumulating path */
    int copied = 0;
    const int ch = cc->channels;
    while(copied < frameCount){
        int need = cc->frameSize - cc->accumFrames;
        int avail = frameCount - copied;
        int take = (avail < need) ? avail : need;
        memcpy(cc->accum + (size_t)cc->accumFrames * (size_t)ch,
               frames + (size_t)copied * (size_t)ch,
               (size_t)take * (size_t)ch * sizeof(float));
        cc->accumFrames += take;
        copied += take;

        if(cc->accumFrames == cc->frameSize){
            int packetBytes = cc_do_encode(cc, cc->accum, outPacket, outCap);
            if(packetBytes > 0 && outBytes) *outBytes = packetBytes;
            cc->accumFrames = 0;
        }
    }

    ma_mutex_unlock(&cc->lock);
    return frameCount;
}

int crosscoder_encode_flush(CrossCoder* cc,
                            int pad,
                            uint8_t* outPacket,
                            int outCap,
                            int* outBytes)
{
    if(outBytes) *outBytes = 0;
    if(!cc) return 0;
    ma_mutex_lock(&cc->lock);
    if(cc->disposed){ ma_mutex_unlock(&cc->lock); return 0; }
    if(!cc->accumulate || cc->accumFrames == 0){
        ma_mutex_unlock(&cc->lock);
        return 1;
    }
    if(pad){
        int ch = cc->channels;
        int remain = cc->frameSize - cc->accumFrames;
        memset(cc->accum + (size_t)cc->accumFrames * (size_t)ch,
               0,
               (size_t)remain * (size_t)ch * sizeof(float));
        cc->accumFrames = cc->frameSize;
        int packetBytes = cc_do_encode(cc, cc->accum, outPacket, outCap);
        if(packetBytes > 0 && outBytes) *outBytes = packetBytes;
        cc->accumFrames = 0;
    } else {
#if INLINE_ENCODER_DEBUG
        fprintf(stderr,"[crosscoder] flush drop partial=%d\n", cc->accumFrames);
#endif
        cc->accumFrames = 0;
    }
    ma_mutex_unlock(&cc->lock);
    return 1;
}

int crosscoder_decode_packet(CrossCoder* cc,
                             const uint8_t* packet,
                             int packetLen,
                             float* outFrames,
                             int maxFrames)
{
    if(!cc || !packet || packetLen < CODEC_FRAME_HEADER_BYTES) return -1;
    if(!outFrames || maxFrames <= 0) return -1;
    if(!cc->codec) return -1;

    CodecID cid = (CodecID)packet[0];
    if(cc->codec->vt.id != cid) {
        /* (Optional) Could rebuild codec here; for simplicity reject. */
        return -1;
    }
    uint16_t plen;
    memcpy(&plen, packet+4, 2);
    if(plen + CODEC_FRAME_HEADER_BYTES != packetLen) return -1;

    int frames = cc->codec->vt.decode(cc->codec,
                                      packet + CODEC_FRAME_HEADER_BYTES,
                                      plen,
                                      outFrames,
                                      maxFrames);
    return frames;
}

/* Runtime configuration functions */
int crosscoder_set_bitrate(CrossCoder* cc, int bitrate) {
    if (!cc) return 0;
    ma_mutex_lock(&cc->lock);
    if (cc->disposed) { 
        ma_mutex_unlock(&cc->lock); 
        return 0; 
    }
    
    cc->bitrate = bitrate;
    
    /* If codec supports runtime bitrate changes, apply it */
    if (cc->codec && cc->codecId == CODEC_ID_OPUS) {
        /* Would call opus-specific bitrate set function if available */
        /* For now, store for next codec recreation */
    }
    
    ma_mutex_unlock(&cc->lock);
    return 1;
}

int crosscoder_set_complexity(CrossCoder* cc, int complexity) {
    if (!cc) return 0;
    ma_mutex_lock(&cc->lock);
    if (cc->disposed) { 
        ma_mutex_unlock(&cc->lock); 
        return 0; 
    }
    
    /* Clamp complexity to valid range */
    if (complexity < 0) complexity = 0;
    if (complexity > 10) complexity = 10;
    cc->complexity = complexity;
    
    /* Store for next codec recreation */
    ma_mutex_unlock(&cc->lock);
    return 1;
}

int crosscoder_set_vbr(CrossCoder* cc, int vbr) {
    if (!cc) return 0;
    ma_mutex_lock(&cc->lock);
    if (cc->disposed) { 
        ma_mutex_unlock(&cc->lock); 
        return 0; 
    }
    
    cc->vbr = vbr ? 1 : 0;
    
    /* Store for next codec recreation */
    ma_mutex_unlock(&cc->lock);
    return 1;
}

int crosscoder_get_bitrate(CrossCoder* cc) {
    return cc ? cc->bitrate : 0;
}

int crosscoder_get_complexity(CrossCoder* cc) {
    return cc ? cc->complexity : 0;
}

int crosscoder_get_vbr(CrossCoder* cc) {
    return cc ? cc->vbr : 0;
}