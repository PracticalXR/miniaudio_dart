// ignore_for_file: camel_case_types, slash_for_doc_comments
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: constant_identifier_names

@JS("Module")
library miniaudio_dart;

import "package:js/js.dart";
import "package:js/js_util.dart";
import "package:miniaudio_dart_platform_interface/miniaudio_dart_platform_interface.dart";

// JS interop
@JS("ccall")
external dynamic _ccall(
    String name, String returnType, List<String> argTypes, List args, Map opts);

// Engine functions
int engine_alloc() => _engine_alloc();
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
Future<int> _engine_init(int self, int periodMs) async =>
    promiseToFuture(_ccall("engine_init", "number", ["number", "number"],
        [self, periodMs], {"async": true}));
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
external void _sound_set_looped(
    int self, bool value, int delay_ms); // FIX: void

// Recorder functions
int recorder_create() => _recorder_create();
Future<int> recorder_init_file(int self, String filename,
        {int sampleRate = 44800,
        int channels = 1,
        int format = AudioFormat.float32}) =>
    _recorder_init_file(self, filename,
        sampleRate: sampleRate, channels: channels, format: format);
Future<int> recorder_init_stream(int self,
        {int sampleRate = 44800,
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
int recorder_get_buffer(int self, int output, int frames_to_read) =>
    _recorder_get_buffer(self, output, frames_to_read);
void recorder_destroy(int self) => _recorder_destroy(self);

// Recorder JS bindings
@JS()
external int _recorder_create();
Future<int> _recorder_init_file(int self, String filename,
        {int sampleRate = 44800,
        int channels = 1,
        int format = AudioFormat.float32}) async =>
    promiseToFuture(_ccall(
        "recorder_init_file",
        "number",
        ["number", "string", "number", "number", "number"],
        [self, filename, sampleRate, channels, format],
        {"async": true}));
Future<int> _recorder_init_stream(int self,
        {int sampleRate = 44800,
        int channels = 1,
        int format = AudioFormat.float32,
        int bufferDurationSeconds = 5}) async =>
    promiseToFuture(_ccall(
        "recorder_init_stream",
        "number",
        ["number", "number", "number", "number", "number"],
        [self, sampleRate, channels, format, bufferDurationSeconds],
        {"async": true}));

@JS()
external int _recorder_start(int self);
@JS()
external int _recorder_stop(int self);
@JS()
external int _recorder_get_available_frames(int self);
@JS()
external bool _recorder_is_recording(int self);
@JS()
external int _recorder_get_buffer(int self, int output, int frames_to_read);
@JS()
external void _recorder_destroy(int self);

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
        {int sampleRate = 44800,
        int channels = 1,
        int format = 4,
        int bufferDuration = 5}) async =>
    promiseToFuture(_ccall(
        "generator_init",
        "number",
        ["number", "number", "number", "number", "number"],
        [self, format, channels, sampleRate, bufferDuration],
        {"async": true}));
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
