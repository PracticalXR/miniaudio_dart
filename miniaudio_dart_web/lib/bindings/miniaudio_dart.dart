// ignore_for_file: camel_case_types, slash_for_doc_comments
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: constant_identifier_names

@JS("Module")
library miniaudio_dart;

import "package:js/js.dart";
import "package:js/js_util.dart" as jsu;
import "package:miniaudio_dart_platform_interface/miniaudio_dart_platform_interface.dart";

// Helper to get Module
Object get _module => jsu.getProperty(jsu.globalThis, 'Module');

// Engine functions
int engine_alloc() => _engine_alloc();
void engine_free(int self) => _engine_free(self);
Future<int> engine_init(int self, int periodMs) => _engine_init(self, periodMs);
void engine_uninit(int self) => _engine_uninit(self);
int engine_start(int self) => _engine_start(self);
int engine_load_sound(int self, int sound, int data, int dataSize, int format,
        int sampleRate, int channels) => // sampleRate, then channels
    _engine_load_sound(
        self, sound, data, dataSize, format, sampleRate, channels);

// Engine JS bindings
@JS()
external int _engine_alloc();
@JS()
external void _engine_free(int self);
Future<int> _engine_init(int self, int periodMs) async {
  final promise = jsu.callMethod(
    _module,
    'ccall',
    [
      'engine_init',
      'number',
      <String>['number', 'number'],
      <Object?>[self, periodMs],
      jsu.jsify({'async': true}),
    ],
  );
  final res = await jsu.promiseToFuture(promise);
  return (res as num).toInt();
}

@JS()
external void _engine_uninit(int self);
@JS()
external int _engine_start(int self);
@JS()
external int _engine_load_sound(int self, int sound, int data, int dataSize,
    int format, int sampleRate, int channels); // sampleRate, then channels

// Sound functions
int sound_alloc() => _sound_alloc();
void sound_unload(int self) => _sound_unload(self);
int sound_play(int self) => _sound_play(self);
int sound_replay(int self) => _sound_replay(self);
void sound_pause(int self) => _sound_pause(self);
void sound_stop(int self) => _sound_stop(self);
double sound_get_volume(int self) => _sound_get_volume(self);
void sound_set_volume(int self, double value) => _sound_set_volume(self, value);
double sound_get_duration(int self) => _sound_get_duration(self);
void sound_set_looped(int self, bool value, int delay_ms) =>
    _sound_set_looped(self, value, delay_ms);

// Sound JS bindings
@JS()
external int _sound_alloc();
@JS()
external void _sound_unload(int sound);
@JS()
external int _sound_play(int self);
@JS()
external int _sound_replay(int self);
@JS()
external void _sound_pause(int self);
@JS()
external void _sound_stop(int self);
@JS()
external double _sound_get_volume(int self);
@JS()
external void _sound_set_volume(int self, double value);
@JS()
external double _sound_get_duration(int self);
@JS()
external void _sound_set_looped(int self, bool value, int delay_ms);

@JS()
external int _recorder_start(int self);
@JS()
external int _recorder_stop(int self);
@JS()
external int _recorder_get_available_frames(int self);
@JS()
external bool _recorder_is_recording(int self);
@JS()
external int _recorder_get_buffer(int self, int output, int floats_to_read);
@JS()
external int _recorder_commit_read_frames(int self, int frames);

@JS()
external void _recorder_destroy(int self);

// Recorder functions
int recorder_create() => _recorder_create();
Future<int> recorder_init_file(int self, String filename,
        {int sampleRate = 48000,
        int channels = 1,
        int format = AudioFormat.float32}) =>
    _recorder_init_file(self, filename,
        sampleRate: sampleRate, channels: channels, format: format);
Future<int> recorder_init_stream(int self,
        {int sampleRate = 48000,
        int channels = 1,
        int format = AudioFormat.float32,
        int bufferDurationSeconds = 5}) =>
    _recorder_init_stream(self,
        sampleRate: sampleRate,
        channels: channels,
        format: format,
        bufferDurationSeconds: bufferDurationSeconds);
int recorder_start(int self) => _recorder_start(self);
int recorder_stop(int self) => _recorder_stop(self);
int recorder_get_available_frames(int self) =>
    _recorder_get_available_frames(self);
bool recorder_is_recording(int self) => _recorder_is_recording(self);
int recorder_get_buffer(int self, int output, int floats_to_read) =>
    _recorder_get_buffer(self, output, floats_to_read);
void recorder_destroy(int self) => _recorder_destroy(self);

// Recorder JS bindings
@JS()
external int _recorder_create();
Future<int> _recorder_init_file(int self, String filename,
    {int sampleRate = 48000,
    int channels = 1,
    int format = AudioFormat.float32}) async {
  final promise = jsu.callMethod(
    _module,
    'ccall',
    [
      'recorder_init_file',
      'number',
      <String>['number', 'string', 'number', 'number', 'number'],
      <Object?>[self, filename, sampleRate, channels, format],
      jsu.jsify({'async': true}),
    ],
  );
  final res = await jsu.promiseToFuture(promise);
  return (res as num).toInt();
}

Future<int> _recorder_init_stream(int self,
    {int sampleRate = 48000,
    int channels = 1,
    int format = AudioFormat.float32,
    int bufferDurationSeconds = 5}) async {
  final promise = jsu.callMethod(
    _module,
    'ccall',
    [
      'recorder_init_stream',
      'number',
      <String>['number', 'number', 'number', 'number', 'number'],
      <Object?>[self, sampleRate, channels, format, bufferDurationSeconds],
      jsu.jsify({'async': true}),
    ],
  );
  final res = await jsu.promiseToFuture(promise);
  return (res as num).toInt();
}

int recorder_acquire_read_region(int self, int outPtrAddr, int outFramesAddr) =>
    _recorder_acquire_read_region(self, outPtrAddr, outFramesAddr);

// New ccall wrapper (Emscripten) for recorder_acquire_read_region
int _recorder_acquire_read_region(int self, int outPtrAddr, int outFramesAddr) {
  final res = jsu.callMethod(
    _module,
    'ccall',
    [
      'recorder_acquire_read_region',
      'number',
      <String>['number', 'number', 'number'],
      <Object?>[self, outPtrAddr, outFramesAddr],
    ],
  ) as num;
  return res.toInt();
}

@JS()
int recorder_commit_read_frames(int self, int frames) =>
    _recorder_commit_read_frames(self, frames);

// Generator functions
int generator_create() => _generator_create();
Future<int> generator_init(int self, int format, int channels, int sample_rate,
        int buffer_duration_seconds) async =>
    _generator_init(self,
        format: format,
        channels: channels,
        sampleRate: sample_rate,
        bufferDuration: buffer_duration_seconds);
int generator_set_waveform(
        int self, int type, double frequency, double amplitude) =>
    _generator_set_waveform(self, type, frequency, amplitude);
int generator_set_pulsewave(
        int self, double frequency, double amplitude, double dutyCycle) =>
    _generator_set_pulsewave(self, frequency, amplitude, dutyCycle);
int generator_set_noise(int self, int type, int seed, double amplitude) =>
    _generator_set_noise(self, type, seed, amplitude);
int generator_get_buffer(int self, int output, int frames_to_read) =>
    _generator_get_buffer(self, output, frames_to_read);
int generator_start(int self) => _generator_start(self);
int generator_stop(int self) => _generator_stop(self);
double generator_get_volume(int self) => _generator_get_volume(self);
void generator_set_volume(int self, double value) =>
    _generator_set_volume(self, value);
int generator_get_available_frames(int self) =>
    _generator_get_available_frames(self);
void generator_destroy(int self) => _generator_destroy(self);

// Generator JS bindings
@JS()
external int _generator_create();
Future<int> _generator_init(int self,
    {int sampleRate = 48000,
    int channels = 1,
    int format = AudioFormat.float32,
    int bufferDuration = 5}) async {
  final promise = jsu.callMethod(
    _module,
    'ccall',
    [
      'generator_init',
      'number',
      <String>['number', 'number', 'number', 'number', 'number'],
      <Object?>[self, format, channels, sampleRate, bufferDuration],
      jsu.jsify({'async': true}),
    ],
  );
  final res = await jsu.promiseToFuture(promise);
  return (res as num).toInt();
}

@JS()
external int _generator_set_waveform(
    int self, int type, double frequency, double amplitude);
@JS()
external int _generator_set_pulsewave(
    int self, double frequency, double amplitude, double dutyCycle);
@JS()
external int _generator_set_noise(
    int self, int type, int seed, double amplitude);
@JS()
external int _generator_start(int self);
@JS()
external int _generator_stop(int self);
@JS()
external double _generator_get_volume(int self);
@JS()
external void _generator_set_volume(int self, double value);
@JS()
external int _generator_get_buffer(int self, int output, int frames_to_read);
@JS()
external int _generator_get_available_frames(int self);
@JS()
external void _generator_destroy(int self);

// Stream player functions
int stream_player_alloc() => _stream_player_alloc();
void stream_player_free(int self) => _stream_player_free(self);
int stream_player_init(int self, int engine, int format, int channels,
        int sampleRate, int bufferMs) =>
    _stream_player_init(self, engine, format, channels, sampleRate, bufferMs);
int stream_player_init_with_engine(int self, int engine, int format,
        int channels, int sampleRate, int bufferMs) =>
    _stream_player_init_with_engine(
        self, engine, format, channels, sampleRate, bufferMs);
void stream_player_uninit(int self) => _stream_player_uninit(self);
int stream_player_start(int self) => _stream_player_start(self);
int stream_player_stop(int self) => _stream_player_stop(self);
void stream_player_clear(int self) => _stream_player_clear(self);
void stream_player_set_volume(int self, double volume) =>
    _stream_player_set_volume(self, volume);
// Write interleaved f32 frames; returns frames written.
int stream_player_write_frames_f32(int self, int dataPtr, int frames) =>
    _stream_player_write_frames_f32(self, dataPtr, frames);

// JS glue (Emscripten ccall)
@JS()
external int _stream_player_alloc();
@JS()
external void _stream_player_free(int self);

int _stream_player_init(int self, int engine, int format, int channels,
    int sampleRate, int bufferMs) {
  final res = jsu.callMethod(
    _module,
    'ccall',
    [
      'stream_player_init',
      'number',
      <String>['number', 'number', 'number', 'number', 'number', 'number'],
      <Object?>[self, engine, format, channels, sampleRate, bufferMs],
    ],
  ) as num;
  return res.toInt();
}

int _stream_player_init_with_engine(int self, int engine, int format,
    int channels, int sampleRate, int bufferMs) {
  final res = jsu.callMethod(
    _module,
    'ccall',
    [
      'stream_player_init_with_engine',
      'number',
      <String>['number', 'number', 'number', 'number', 'number', 'number'],
      <Object?>[self, engine, format, channels, sampleRate, bufferMs],
    ],
  ) as num;
  return res.toInt();
}

@JS()
external void _stream_player_uninit(int self);

@JS()
external int _stream_player_start(int self);

@JS()
external int _stream_player_stop(int self);

@JS()
external void _stream_player_clear(int self);

@JS()
external void _stream_player_set_volume(int self, double volume);

int _stream_player_write_frames_f32(int self, int dataPtr, int frames) {
  final res = jsu.callMethod(
    _module,
    'ccall',
    [
      'stream_player_write_frames_f32',
      'number',
      <String>['number', 'number', 'number'],
      <Object?>[self, dataPtr, frames],
    ],
  ) as num;
  return res.toInt();
}

@JS()
external int _recorder_attach_inline_opus(
    int self, int sampleRate, int channels);
@JS()
external int _recorder_encoder_pending(int self);
@JS()
external int _recorder_encoder_dequeue_packet(int self, int outPtr, int cap);

@JS()
external int _stream_player_push_encoded_packet(
    int self, int dataPtr, int length);

// Convenience wrappers (ccall if needed async = false)
int recorder_attach_inline_opus(int self, int sampleRate, int channels) =>
    _recorder_attach_inline_opus(self, sampleRate, channels);
int recorder_encoder_pending(int self) => _recorder_encoder_pending(self);
int recorder_encoder_dequeue_packet(int self, int outPtr, int cap) =>
    _recorder_encoder_dequeue_packet(self, outPtr, cap);

int stream_player_push_encoded_packet(int self, int dataPtr, int length) =>
    _stream_player_push_encoded_packet(self, dataPtr, length);

// Ensure these JS externs exist (add if missing):

@JS()
external int _recorder_inline_encoder_feed_f32(
    int self, int dataPtr, int frames);
@JS()
external int _recorder_inline_encoder_flush(int self, int pad);

int recorder_inline_encoder_feed_f32(int self, int dataPtr, int frames) =>
    _recorder_inline_encoder_feed_f32(self, dataPtr, frames);
int recorder_inline_encoder_flush(int self, int pad) =>
    _recorder_inline_encoder_flush(self, pad);
