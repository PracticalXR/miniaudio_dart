#include "../include/record.h"
#include "../include/codec_inline_encoder.h"
#include "../include/codec.h"
#include "../include/codec_opus_diag.h"
#include <stdio.h> /* for fprintf, stderr */

#ifdef HAVE_OPUS
/* Ensure Opus application constants are visible here. */
#  if defined(OPUS_HEADER_FLAT)
#    if __has_include(<opus.h>)
#      include <opus.h>
#    else
#      error "OPUS_HEADER_FLAT defined but <opus.h> not found"
#    endif
#  else
#    if __has_include(<opus/opus.h>)
#      include <opus/opus.h>
#    elif __has_include(<opus.h>)
#      include <opus.h>
#      define OPUS_HEADER_FLAT 1
#    else
#      warning "HAVE_OPUS set but Opus header not found; disabling opus path."
#      undef HAVE_OPUS
#    endif
#  endif
#endif

static void data_callback(ma_device *pDevice, void *pOutput, const void *pInput,
                          ma_uint32 frameCount) {
  Recorder *r = (Recorder *)pDevice->pUserData;
  ma_uint32 framesRemaining = frameCount;
  const ma_uint8 *in = (const ma_uint8 *)pInput;

  while (framesRemaining > 0) {
    ma_uint32 writable = framesRemaining;
    void *pWrite = NULL;
    if (ma_pcm_rb_acquire_write(&r->rb, &writable, &pWrite) != MA_SUCCESS ||
        writable == 0)
      break;
    memcpy(pWrite, in, writable * r->frameSize);
    ma_pcm_rb_commit_write(&r->rb, writable);
    in += writable * r->frameSize;
    framesRemaining -= writable;
  }

  if (r->is_file_recording) {
    ma_encoder_write_pcm_frames(&r->encoder, pInput, frameCount, NULL);
  }

  // After copying into ring buffer, feed inline encoder (if enabled) as float.
  if (r->inlineEncoder) {
      if (r->format == ma_format_f32) {
          #ifdef INLINE_ENCODER_USES_FEED
          inline_encoder_feed(r->inlineEncoder, (const float*)pInput, (int)frameCount);
          #else
          inline_encoder_on_capture(r->inlineEncoder, (const float*)pInput, (int)frameCount);
          #endif
      }
  }
  (void)pOutput;
}

Recorder *recorder_create(void) {
  Recorder *recorder = (Recorder *)malloc(sizeof(Recorder));
  if (!recorder)
    return NULL;
  memset(recorder, 0, sizeof(Recorder));
  return recorder;
}

void recorder_destroy(Recorder *recorder) {
  if (recorder) {
    ma_device_uninit(&recorder->device);
    if (recorder->context_initialized) {
        ma_context_uninit(&recorder->context);
    }
    recorder_free_capture_cache(recorder);
    if (recorder->is_file_recording) {
      ma_encoder_uninit(&recorder->encoder);
      free(recorder->filename);
    }
    circular_buffer_uninit(&recorder->circular_buffer);
    ma_pcm_rb_uninit(&recorder->rb);
    free(recorder);
  }
}

// Shared init (file recording path)
static RecorderResult recorder_init_common(Recorder *recorder,
                                           const char *filename,
                                           int sample_rate, int channels,
                                           ma_format format,
                                           int buffer_duration_seconds) {
  if (!recorder || channels <= 0 || sample_rate <= 0)
    return RECORDER_ERROR_INVALID_ARGUMENT;

  recorder->is_file_recording = (filename != NULL);
  recorder->sample_rate = sample_rate;
  recorder->channels = channels;
  recorder->format = format;

  recorder->frameSize = (ma_uint32)(ma_get_bytes_per_sample(format) * channels);

  size_t buffer_size_in_bytes = (size_t)sample_rate * (size_t)channels *
                                ma_get_bytes_per_sample(format) *
                                (size_t)buffer_duration_seconds;
  circular_buffer_init(&recorder->circular_buffer, buffer_size_in_bytes);

  // Ring buffer for monitoring / streaming API (optional even in file mode)
  ma_uint32 capacityFrames = (ma_uint32)(sample_rate * buffer_duration_seconds);
  if (capacityFrames < 1024)
    capacityFrames = 1024;
  if (ma_pcm_rb_init(format, channels, capacityFrames, NULL, NULL,
                     &recorder->rb) != MA_SUCCESS) {
    circular_buffer_uninit(&recorder->circular_buffer);
    return RECORDER_ERROR_OUT_OF_MEMORY;
  }

  if (recorder->is_file_recording) {
    recorder->filename = strdup(filename);
    if (!recorder->filename) {
      ma_pcm_rb_uninit(&recorder->rb);
      circular_buffer_uninit(&recorder->circular_buffer);
      return RECORDER_ERROR_OUT_OF_MEMORY;
    }
    recorder->encoder_config = ma_encoder_config_init(
        ma_encoding_format_wav, format, channels, sample_rate);
    if (ma_encoder_init_file(recorder->filename, &recorder->encoder_config,
                             &recorder->encoder) != MA_SUCCESS) {
      free(recorder->filename);
      ma_pcm_rb_uninit(&recorder->rb);
      circular_buffer_uninit(&recorder->circular_buffer);
      return RECORDER_ERROR_UNKNOWN;
    }
  }

  recorder->device_config = ma_device_config_init(ma_device_type_capture);
  recorder->device_config.capture.format = format;
  recorder->device_config.capture.channels = channels;
  recorder->device_config.sampleRate = sample_rate;
  recorder->device_config.dataCallback = data_callback;
  recorder->device_config.pUserData = recorder;

  if (ma_device_init(NULL, &recorder->device_config, &recorder->device) !=
      MA_SUCCESS) {
    if (recorder->is_file_recording) {
      ma_encoder_uninit(&recorder->encoder);
      free(recorder->filename);
    }
    ma_pcm_rb_uninit(&recorder->rb);
    circular_buffer_uninit(&recorder->circular_buffer);
    return RECORDER_ERROR_UNKNOWN;
  }

  recorder->is_recording = false;
  recorder->user_data = NULL;
  return RECORDER_OK;
}

RecorderResult recorder_init_file(Recorder *recorder, const char *filename,
                                  int sample_rate, int channels,
                                  ma_format format) {
  if (!filename)
    return RECORDER_ERROR_INVALID_ARGUMENT;
  return recorder_init_common(recorder, filename, sample_rate, channels, format,
                              5);
}

// Streaming-only init (no file encoder, but MUST init device)
RecorderResult recorder_init_stream(Recorder *recorder, int sample_rate,
                                    int channels, ma_format format,
                                    int buffer_duration_seconds) {
  if (!recorder || channels <= 0 || sample_rate <= 0)
    return RECORDER_ERROR_INVALID_ARGUMENT;

  recorder->is_file_recording = false;
  recorder->sample_rate = sample_rate;
  recorder->channels = channels;
  recorder->format = format;
  recorder->frameSize = (ma_uint32)(ma_get_bytes_per_sample(format) * channels);

  ma_uint32 capacityFrames = (ma_uint32)(sample_rate * buffer_duration_seconds);
  if (capacityFrames < 1024) capacityFrames = 1024;
  if (ma_pcm_rb_init(format, channels, capacityFrames, NULL, NULL, &recorder->rb) != MA_SUCCESS) {
      return RECORDER_ERROR_OUT_OF_MEMORY;
  }

  recorder->device_config = ma_device_config_init(ma_device_type_capture);
  recorder->device_config.capture.format   = format;
  recorder->device_config.capture.channels = channels;
  recorder->device_config.sampleRate       = sample_rate;
  recorder->device_config.dataCallback     = data_callback;
  recorder->device_config.pUserData        = recorder;

  if (ma_device_init(NULL, &recorder->device_config, &recorder->device) != MA_SUCCESS) {
      /* Fallback once to f32 if user requested something else. */
      if (format != ma_format_f32) {
          recorder->format = ma_format_f32;
          recorder->frameSize = (ma_uint32)(ma_get_bytes_per_sample(ma_format_f32) * channels);
          ma_pcm_rb_uninit(&recorder->rb);
          if (ma_pcm_rb_init(ma_format_f32, channels, capacityFrames, NULL, NULL, &recorder->rb) != MA_SUCCESS) {
              return RECORDER_ERROR_OUT_OF_MEMORY;
          }
          recorder->device_config.capture.format = ma_format_f32;
          if (ma_device_init(NULL, &recorder->device_config, &recorder->device) != MA_SUCCESS) {
              ma_pcm_rb_uninit(&recorder->rb);
              return RECORDER_ERROR_UNKNOWN;
          }
      } else {
          ma_pcm_rb_uninit(&recorder->rb);
          return RECORDER_ERROR_UNKNOWN;
      }
  }

  recorder->is_recording = false;
  recorder->user_data = NULL;
  return RECORDER_OK;
}

RecorderResult recorder_start(Recorder *recorder) {
  if (!recorder)
    return RECORDER_ERROR_INVALID_ARGUMENT;
  if (recorder->is_recording)
    return RECORDER_OK; /* idempotent */

  if (ma_device_start(&recorder->device) != MA_SUCCESS)
    return RECORDER_ERROR_UNKNOWN;

  recorder->is_recording = true;
  return RECORDER_OK;
}

RecorderResult recorder_stop(Recorder *recorder) {
  if (!recorder)
    return RECORDER_ERROR_INVALID_ARGUMENT;
  if (!recorder->is_recording)
    return RECORDER_OK; /* idempotent */

  ma_device_stop(&recorder->device);
  recorder->is_recording = false;
  return RECORDER_OK;
}

bool recorder_is_recording(const Recorder *recorder) {
  return recorder && recorder->is_recording;
}

// Legacy circular buffer API (still present if file mode used)
int recorder_get_buffer(Recorder *recorder, float *output, int floats_to_read) {
  if (!recorder || !output || floats_to_read <= 0)
    return 0;
  size_t available_floats =
      circular_buffer_get_available_floats(&recorder->circular_buffer);
  size_t to_read = (floats_to_read < available_floats) ? (size_t)floats_to_read
                                                       : available_floats;
  return (int)circular_buffer_read(&recorder->circular_buffer, output, to_read);
}

int recorder_get_available_frames(Recorder *recorder) {
    if (!recorder || recorder->channels <= 0)
        return 0;
    if (recorder->is_file_recording) {
        size_t available_floats =
            circular_buffer_get_available_floats(&recorder->circular_buffer);
        if (available_floats == 0) return 0;
        return (int)(available_floats / (size_t)recorder->channels);
    }
    /* Streaming mode: use ring buffer */
    return (int)ma_pcm_rb_available_read(&recorder->rb);
}

int recorder_get_available_frames_rb(Recorder *recorder) {
    if (!recorder || recorder->channels <= 0) return 0;
    return (int)ma_pcm_rb_available_read(&recorder->rb);
}

/* Ring buffer streaming helpers */
static int recorder_acquire_read(Recorder *r, void **outPtr, int *outFrames) {
    if (!r || !outPtr || !outFrames) return 0;
    ma_uint32 available = ma_pcm_rb_available_read(&r->rb);
    if (available == 0) {
        *outPtr = NULL;
        *outFrames = 0;
        return 1;
    }
    void *pRead = NULL;
    if (ma_pcm_rb_acquire_read(&r->rb, &available, &pRead) != MA_SUCCESS)
        return 0;
    *outPtr = pRead;
    *outFrames = (int)available;
    return 1;
}

int recorder_acquire_read_region(Recorder *r, uintptr_t *outPtr, int *outFrames) {
    if (!outPtr || !outFrames) return 0;
    void *p = NULL;
    int frames = 0;
    if (!recorder_acquire_read(r, &p, &frames)) return 0;
    *outPtr = (uintptr_t)p;
    *outFrames = frames;
    return 1;
}

int recorder_commit_read_frames(Recorder *r, int frames) {
    if (!r || frames < 0) return 0;
    if (frames == 0) return 1; // nothing to advance
    ma_pcm_rb_commit_read(&r->rb, (ma_uint32)frames);
    return 1;
}

// Add helpers & integrate (only showing new / changed parts)

// Initialize context lazily
static int recorder_ensure_context(Recorder* r) {
    if (!r) return 0;
    if (r->context_initialized) return 1;
    ma_context_config cfg = ma_context_config_init();
    if (ma_context_init(NULL, 0, &cfg, &r->context) != MA_SUCCESS) return 0;
    r->context_initialized = true;
    return 1;
}

extern void recorder_free_capture_cache(Recorder* r) {
    if (!r) return;
    if (r->captureInfos) {
        free(r->captureInfos);
        r->captureInfos = NULL;
    }
    r->captureCount = 0;
}

int recorder_refresh_capture_devices(Recorder* r) {
    if (!r) return 0;
    if (!recorder_ensure_context(r)) return 0;

    ma_device_info* pPlayback = NULL;
    ma_uint32 playbackCount = 0;
    ma_device_info* pCapture = NULL;
    ma_uint32 captureCount = 0;

    if (ma_context_get_devices(&r->context,
                               &pPlayback, &playbackCount,
                               &pCapture, &captureCount) != MA_SUCCESS) {
        return 0;
    }

    recorder_free_capture_cache(r);
    if (captureCount == 0) {
        r->captureGeneration++;
        return 1;
    }

    r->captureInfos = (CaptureDeviceInfo*)malloc(sizeof(CaptureDeviceInfo) * captureCount);
    if (!r->captureInfos) return 0;

    for (ma_uint32 i = 0; i < captureCount; i++) {
        CaptureDeviceInfo* dst = &r->captureInfos[i];
        ma_device_info* src = &pCapture[i];
        memset(dst, 0, sizeof(*dst));
        strncpy(dst->name, src->name, 256 - 1);
        dst->id = src->id;
        dst->isDefault = src->isDefault;
    }
    r->captureCount = captureCount;
    r->captureGeneration++;
    return 1;
}

ma_uint32 recorder_get_capture_device_count(Recorder* r) {
    return r ? r->captureCount : 0;
}

int recorder_get_capture_device_name(Recorder* r,
                                     ma_uint32 index,
                                     char* outName,
                                     ma_uint32 capName,
                                     ma_bool32* pIsDefault) {
    if (!r || index >= r->captureCount || !outName || capName == 0) return 0;
    CaptureDeviceInfo* info = &r->captureInfos[index];
    strncpy(outName, info->name, capName - 1);
    outName[capName - 1] = '\0';
    if (pIsDefault) *pIsDefault = info->isDefault;
    return 1;
}

ma_uint32 recorder_get_capture_device_generation(Recorder* r) {
    return r ? r->captureGeneration : 0;
}

int recorder_select_capture_device_by_index(Recorder* r, ma_uint32 index) {
    if (!r || index >= r->captureCount) return 0;

    /* Preserve state */
    bool wasRecording = r->is_recording;
    if (wasRecording) {
        ma_device_stop(&r->device);
        r->is_recording = false;
    }
    ma_device_uninit(&r->device);

    /* Rebuild device config with chosen ID */
    r->device_config = ma_device_config_init(ma_device_type_capture);
    r->device_config.capture.format   = r->format;
    r->device_config.capture.channels = r->channels;
    r->device_config.sampleRate       = r->sample_rate;
    r->device_config.dataCallback     = data_callback;
    r->device_config.pUserData        = r;
    r->device_config.capture.pDeviceID = &r->captureInfos[index].id;

    if (ma_device_init(&r->context, &r->device_config, &r->device) != MA_SUCCESS) {
        /* Attempt fallback to default (NULL context / default device) */
        r->device_config.capture.pDeviceID = NULL;
        if (ma_device_init(NULL, &r->device_config, &r->device) != MA_SUCCESS) {
            return 0;
        }
    }

    if (wasRecording) {
        if (ma_device_start(&r->device) == MA_SUCCESS) {
            r->is_recording = true;
        }
    }

    r->captureGeneration++; /* device change event */
    return 1;
}

/* ================= Inline Opus Encoder Integration ================= */

int recorder_attach_inline_opus(Recorder* r, int sample_rate, int channels) {
#ifdef HAVE_OPUS
    if (!r) return 0;
    if (r->inlineEncoder) return 1;
    if (sample_rate != r->sample_rate || channels != r->channels) return 0;
    if (r->format != ma_format_f32) return 0;

#if !defined(OPUS_APPLICATION_AUDIO)
#define OPUS_APPLICATION_AUDIO 2049
#endif

    CodecConfig cfg;
    cfg.sample_rate     = sample_rate;
    cfg.channels        = channels;
    cfg.bits_per_sample = 32;

    Codec* c = codec_create_opus(&cfg, OPUS_APPLICATION_AUDIO);
    if (!c) {
        fprintf(stderr,"[opus] create failed: %s (sr=%d ch=%d)\n",
                codec_opus_last_error(), cfg.sample_rate, cfg.channels);
        return 0;
    }

    InlineEncoder* ie = (InlineEncoder*)calloc(1, sizeof(InlineEncoder));
    if (!ie) {
        if (c->vt.destroy) c->vt.destroy(c);
        return 0;
    }
    if (!inline_encoder_init(ie, c, channels, 32, 128)) {
        if (c->vt.destroy) c->vt.destroy(c);
        free(ie);
        return 0;
    }
    r->inlineEncoder = ie;
    return 1;
#else
    (void)r; (void)sample_rate; (void)channels;
    return 0;
#endif
}

int recorder_detach_inline_encoder(Recorder* r) {
    if (!r) return 0;
    if (!r->inlineEncoder) return 1;
    inline_encoder_uninit(r->inlineEncoder);
    free(r->inlineEncoder);
    r->inlineEncoder = NULL;
    return 1;
}

int recorder_encoder_dequeue_packet(Recorder* r, void* outBuf, int cap) {
    if (!r || !r->inlineEncoder || !outBuf || cap <= 0) return 0;
    int len = inline_encoder_dequeue(r->inlineEncoder, (uint8_t*)outBuf, (uint16_t)cap);
    if (len < 0) return 0;
    return len;
}

uint32_t recorder_encoder_pending(Recorder* r) {
    if (!r || !r->inlineEncoder) return 0;
    return inline_encoder_pending(r->inlineEncoder);
}

// Ensure implementations exist (already added previously). If not, include them near other inline encoder funcs:

int recorder_inline_encoder_feed_f32(Recorder* r, const float* interleaved, int frameCount) {
    if (!r || !interleaved || frameCount <= 0) return 0;
    if (!r->inlineEncoder) return 0;
    inline_encoder_on_capture(r->inlineEncoder, interleaved, frameCount);
    return frameCount;
}

int recorder_inline_encoder_flush(Recorder* r, int padWithZeros) {
    if (!r || !r->inlineEncoder) return 0;
    return inline_encoder_flush(r->inlineEncoder, padWithZeros ? 1 : 0);
}