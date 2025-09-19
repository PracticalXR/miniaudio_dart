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
        int sampleRate, int channels) =>
    _engine_load_sound(
        self, sound, data, dataSize, format, sampleRate, channels);

// Engine JS bindings
@JS()
external int _engine_alloc();
@JS()
external void _engine_free(int self);
@JS()
external int _engine_start(int self);
@JS()
external void _engine_uninit(int self);
@JS()
external int _engine_load_sound(int self, int sound, int data, int dataSize,
    int format, int sampleRate, int channels);

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

// Sound functions
int sound_alloc() => _sound_alloc();
void sound_free(int self) => _sound_free(self);
void sound_unload(int self) => _sound_unload(self);
int sound_play(int self) => _sound_play(self);
int sound_replay(int self) => _sound_replay(self);
void sound_pause(int self) => _sound_pause(self);
void sound_stop(int self) => _sound_stop(self);
double sound_get_volume(int self) => _sound_get_volume(self);
void sound_set_volume(int self, double volume) =>
    _sound_set_volume(self, volume);
double sound_get_duration(int self) => _sound_get_duration(self);
void sound_set_looped(int self, bool enabled, int delayMs) =>
    _sound_set_looped(self, enabled, delayMs);

@JS()
external int _sound_alloc();
@JS()
external void _sound_free(int self);
@JS()
external void _sound_unload(int self);
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
external void _sound_set_volume(int self, double volume);
@JS()
external double _sound_get_duration(int self);
@JS()
external void _sound_set_looped(int self, bool enabled, int delayMs);

// Recorder functions
int recorder_create() => _recorder_create();
void recorder_destroy(int self) => _recorder_destroy(self);
int recorder_start(int self) => _recorder_start(self);
int recorder_stop(int self) => _recorder_stop(self);
int recorder_is_recording(int self) => _recorder_is_recording(self);
int recorder_get_available_frames(int self) =>
    _recorder_get_available_frames(self);
int recorder_acquire_read_region(int self, int ptrOut, int framesOut) =>
    _recorder_acquire_read_region(self, ptrOut, framesOut);
void recorder_commit_read_frames(int self, int frames) =>
    _recorder_commit_read_frames(self, frames);

// New unified recorder_init function
Future<int> recorder_init(int self, int configPtr) async {
  final promise = jsu.callMethod(
    _module,
    'ccall',
    [
      'recorder_init',
      'number',
      <String>['number', 'number'],
      <Object?>[self, configPtr],
      jsu.jsify({'async': true}),
    ],
  );
  final res = await jsu.promiseToFuture(promise);
  return (res as num).toInt();
}

@JS()
external int _recorder_create();
@JS()
external void _recorder_destroy(int self);
@JS()
external int _recorder_start(int self);
@JS()
external int _recorder_stop(int self);
@JS()
external int _recorder_is_recording(int self);
@JS()
external int _recorder_get_available_frames(int self);
@JS()
external int _recorder_acquire_read_region(int self, int ptrOut, int framesOut);
@JS()
external void _recorder_commit_read_frames(int self, int frames);

// StreamPlayer functions
int stream_player_alloc() => _stream_player_alloc();
void stream_player_free(int self) => _stream_player_free(self);
void stream_player_uninit(int self) => _stream_player_uninit(self);
int stream_player_start(int self) => _stream_player_start(self);
int stream_player_stop(int self) => _stream_player_stop(self);
void stream_player_clear(int self) => _stream_player_clear(self);
void stream_player_set_volume(int self, double volume) =>
    _stream_player_set_volume(self, volume);
int stream_player_write_frames_f32(int self, int data, int frames) =>
    _stream_player_write_frames_f32(self, data, frames);
int stream_player_push_encoded_packet(int self, int data, int bytes) =>
    _stream_player_push_encoded_packet(self, data, bytes);

// StreamPlayer with config struct (matching FFI)
int stream_player_init_with_engine(int self, int engine, int configPtr) =>
    _stream_player_init_with_engine(self, engine, configPtr);

int _stream_player_init_with_engine(int self, int engine, int configPtr) {
  final res = jsu.callMethod(
    _module,
    'ccall',
    [
      'stream_player_init_with_engine',
      'number',
      <String>['number', 'number', 'number'],
      <Object?>[self, engine, configPtr],
    ],
  ) as num;
  return res.toInt();
}

@JS()
external int _stream_player_alloc();
@JS()
external void _stream_player_free(int self);
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
@JS()
external int _stream_player_write_frames_f32(int self, int data, int frames);
@JS()
external int _stream_player_push_encoded_packet(int self, int data, int bytes);

// CrossCoder functions
int crosscoder_create(
        int configPtr, int codecId, int application, int accumulate) =>
    _crosscoder_create(configPtr, codecId, application, accumulate);
void crosscoder_destroy(int self) => _crosscoder_destroy(self);
int crosscoder_frame_size(int self) => _crosscoder_frame_size(self);
int crosscoder_encode_push_f32(int self, int framesPtr, int frameCount,
        int outPacketPtr, int outCap, int outBytesPtr) =>
    _crosscoder_encode_push_f32(
        self, framesPtr, frameCount, outPacketPtr, outCap, outBytesPtr);
int crosscoder_decode_packet(int self, int packetPtr, int packetLen,
        int outFramesPtr, int maxFrames) =>
    _crosscoder_decode_packet(
        self, packetPtr, packetLen, outFramesPtr, maxFrames);

@JS()
external int _crosscoder_create(
    int configPtr, int codecId, int application, int accumulate);
@JS()
external void _crosscoder_destroy(int self);
@JS()
external int _crosscoder_frame_size(int self);
@JS()
external int _crosscoder_encode_push_f32(int self, int framesPtr,
    int frameCount, int outPacketPtr, int outCap, int outBytesPtr);
@JS()
external int _crosscoder_decode_packet(
    int self, int packetPtr, int packetLen, int outFramesPtr, int maxFrames);

// Generator functions
int generator_create() => _generator_create();
void generator_destroy(int self) => _generator_destroy(self);
double generator_get_volume(int self) => _generator_get_volume(self);
void generator_set_volume(int self, double volume) =>
    _generator_set_volume(self, volume);
int generator_get_available_frames(int self) =>
    _generator_get_available_frames(self);
int generator_get_buffer(int self, int ptr, int frames) =>
    _generator_get_buffer(self, ptr, frames);

Future<int> generator_init(int self, int format, int channels, int sampleRate,
    int bufferDurationSeconds) async {
  final promise = jsu.callMethod(
    _module,
    'ccall',
    [
      'generator_init',
      'number',
      <String>['number', 'number', 'number', 'number', 'number'],
      <Object?>[self, format, channels, sampleRate, bufferDurationSeconds],
      jsu.jsify({'async': true}),
    ],
  );
  final res = await jsu.promiseToFuture(promise);
  return (res as num).toInt();
}

int generator_start(int self) => _generator_start(self);
int generator_stop(int self) => _generator_stop(self);
int generator_set_waveform(
        int self, int type, double frequency, double amplitude) =>
    _generator_set_waveform(self, type, frequency, amplitude);
int generator_set_pulsewave(
        int self, double frequency, double amplitude, double dutyCycle) =>
    _generator_set_pulsewave(self, frequency, amplitude, dutyCycle);
int generator_set_noise(int self, int type, int seed, double amplitude) =>
    _generator_set_noise(self, type, seed, amplitude);

@JS()
external int _generator_create();
@JS()
external void _generator_destroy(int self);
@JS()
external double _generator_get_volume(int self);
@JS()
external void _generator_set_volume(int self, double volume);
@JS()
external int _generator_get_available_frames(int self);
@JS()
external int _generator_get_buffer(int self, int ptr, int frames);
@JS()
external int _generator_start(int self);
@JS()
external int _generator_stop(int self);
@JS()
external int _generator_set_waveform(
    int self, int type, double frequency, double amplitude);
@JS()
external int _generator_set_pulsewave(
    int self, double frequency, double amplitude, double dutyCycle);
@JS()
external int _generator_set_noise(
    int self, int type, int seed, double amplitude);
