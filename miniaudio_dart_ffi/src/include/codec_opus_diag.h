#ifndef CODEC_OPUS_DIAG_H
#define CODEC_OPUS_DIAG_H
#ifdef HAVE_OPUS
const char* codec_opus_last_error(void);
#else
static inline const char* codec_opus_last_error(void){ return "opus disabled"; }
#endif
#endif