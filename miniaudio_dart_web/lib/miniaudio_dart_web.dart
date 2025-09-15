// ignore_for_file: omit_local_variable_types

import "dart:async";
import "dart:typed_data";
import "package:miniaudio_dart_platform_interface/miniaudio_dart_platform_interface.dart";
import "package:miniaudio_dart_web/bindings/miniaudio_dart.dart" as wasm;
import "package:miniaudio_dart_web/bindings/memory_web.dart" as mem;

// Provide the function consumed by the stub import.
MiniaudioDartPlatformInterface registeredInstance() => MiniaudioDartWeb._();

class MiniaudioDartWeb extends MiniaudioDartPlatformInterface {
  MiniaudioDartWeb._();

  static void registerWith(dynamic _) => MiniaudioDartWeb._();

  @override
  PlatformEngine createEngine() {
    final self = wasm.engine_alloc();
    if (self == 0) throw MiniaudioDartPlatformOutOfMemoryException();
    return WebEngine(self);
  }

  @override
  PlatformRecorder createRecorder() => WebRecorder(wasm.recorder_create());

  @override
  PlatformGenerator createGenerator() => WebGenerator(wasm.generator_create());

  // Streaming player factory
  @override
  PlatformStreamPlayer createStreamPlayer({
    required PlatformEngine engine,
    required int format,
    required int channels,
    required int sampleRate,
    int bufferMs = 240,
  }) {
    if (format != AudioFormat.float32) {
      throw MiniaudioDartPlatformException(
        "Web StreamPlayer supports only AudioFormat.float32",
      );
    }
    final eng = (engine as WebEngine)._self;
    final sp = wasm.stream_player_alloc();
    if (sp == 0) {
      throw MiniaudioDartPlatformOutOfMemoryException();
    }
    // use with_engine variant (Engine* -> ma_engine*)
    final ok = wasm.stream_player_init_with_engine(
        sp, eng, format, channels, sampleRate, bufferMs);
    if (ok == 0) {
      throw MiniaudioDartPlatformException("stream_player_init failed");
    }
    return WebStreamPlayer._(sp, channels);
  }
}

// Optional interface; align with your platform_interface
final class WebStreamPlayer implements PlatformStreamPlayer {
  WebStreamPlayer._(this._self, this._channels);
  final int _self;
  final int _channels;

  // Reusable scratch buffer (in bytes).
  int _scratchPtr = 0;
  int _scratchBytes = 0;

  double _volume = 1.0;
  @override
  double get volume => _volume;
  @override
  set volume(double v) {
    final clamped = (v.isNaN ? 0.0 : v).clamp(0.0, 100.0).toDouble();
    _volume = clamped;
    // If you have a wasm export, call it; otherwise apply gain in writeFloat32.
    try {
      wasm.stream_player_set_volume(_self, clamped);
    } catch (_) {}
  }

  @override
  void start() {
    final ok = wasm.stream_player_start(_self);
    if (ok == 0) {
      throw MiniaudioDartPlatformException("stream_player_start failed");
    }
  }

  @override
  void stop() {
    final ok = wasm.stream_player_stop(_self);
    if (ok == 0) {
      throw MiniaudioDartPlatformException("stream_player_stop failed");
    }
  }

  @override
  void clear() {
    wasm.stream_player_clear(_self);
  }

  // Write interleaved Float32 samples; returns frames written.
  // Ensures 4-byte alignment and correct byte length.
  @override
  int writeFloat32(Float32List interleaved) {
    if (interleaved.isEmpty) return 0;
    final floats = interleaved.lengthInBytes ~/ 4;
    if (floats % _channels != 0) {
      throw MiniaudioDartPlatformException(
          "writeFloat32: floats ($floats) not divisible by channels ($_channels)");
    }
    final frames = floats ~/ _channels;
    final bytes = interleaved.lengthInBytes;

    // Ensure aligned, contiguous buffer in WASM heap.
    if (_scratchBytes < bytes) {
      if (_scratchPtr != 0) mem.free(_scratchPtr);
      _scratchPtr = mem.allocate(bytes);
      _scratchBytes = bytes;
      assert((_scratchPtr & 3) == 0, "malloc returned unaligned pointer");
    }
    mem.copyFromTypedData(_scratchPtr, interleaved);

    final written =
        wasm.stream_player_write_frames_f32(_self, _scratchPtr, frames);
    return written;
  }

  @override
  void dispose() {
    if (_scratchPtr != 0) {
      mem.free(_scratchPtr);
      _scratchPtr = 0;
      _scratchBytes = 0;
    }
    wasm.stream_player_uninit(_self);
  }
}

final class WebEngine implements PlatformEngine {
  WebEngine(this._self);
  final int _self;

  @override
  EngineState state = EngineState.uninit;
  Future<void>? _initPending; // serialize init

  @override
  Future<void> init(int periodMs) async {
    if (state == EngineState.init) return;
    if (_initPending != null) {
      await _initPending;
      return;
    }
    final c = Completer<void>();
    _initPending = c.future;
    try {
      final ok = await wasm.engine_init(_self, periodMs);
      if (ok == 0) {
        throw MiniaudioDartPlatformException('engine_init failed (0)');
      }
      state = EngineState.init;
      c.complete();
    } catch (e) {
      c.completeError(e);
      rethrow;
    } finally {
      _initPending = null;
    }
  }

  @override
  void dispose() {
    wasm.engine_uninit(_self);
  }

  @override
  void start() {
    final pending = _initPending;
    if (pending != null) {
      // Defer start until init finishes to avoid Asyncify re-entry/races.
      pending.whenComplete(() {
        wasm.engine_start(_self);
      });
      return;
    }
    wasm.engine_start(_self);
  }

  @override
  Future<PlatformSound> loadSound(AudioData audioData) async {
    if (_initPending != null) {
      await _initPending; // wait for engine to be ready
    }
    final bytes = audioData.buffer.lengthInBytes;
    if (bytes == 0) {
      throw MiniaudioDartPlatformException("loadSound: empty buffer");
    }
    final dataPtr = mem.allocate(bytes);
    try {
      mem.copyBytes(dataPtr, audioData.buffer.buffer);

      final sound = wasm.sound_alloc();
      if (sound == 0) {
        mem.free(dataPtr);
        throw MiniaudioDartPlatformOutOfMemoryException();
      }

      // IMPORTANT:
      // - C expects data_size in BYTES for both raw PCM and encoded paths.
      // - C expects (format, sampleRate, channels) order.
      final result = wasm.engine_load_sound(
        _self,
        sound,
        dataPtr,
        bytes, // pass bytes
        audioData.format,
        audioData.sampleRate, // sampleRate first
        audioData.channels, // channels last
      );
      if (result == 0) {
        mem.free(dataPtr);
        throw MiniaudioDartPlatformException("engine_load_sound failed (0)");
      }

      return WebSound._fromPtrs(sound, dataPtr);
    } catch (e) {
      mem.free(dataPtr);
      rethrow;
    }
  }

  // WebAudio cannot select output devices (no setSinkId for AudioContext).
  Future<List<(String name, bool isDefault)>> enumeratePlaybackDevices() async {
    // WebAudio: no output device selection; return a single default device.
    return const [("Default Output", true)];
  }

  Future<bool> selectPlaybackDeviceByIndex(int index) async {
    // No-op on web
    return index == 0;
  }
}

final class WebSound implements PlatformSound {
  WebSound._fromPtrs(this._self, this._dataPtr);

  final int _self;
  final int _dataPtr;

  late var _volume = wasm.sound_get_volume(_self);
  @override
  double get volume => _volume;
  @override
  set volume(double value) {
    _volume = value;
    wasm.sound_set_volume(_self, value);
  }

  @override
  late final double duration = wasm.sound_get_duration(_self);

  var _looping = (false, 0);
  @override
  PlatformSoundLooping get looping => _looping;

  @override
  set looping(PlatformSoundLooping value) {
    _looping = value;
    final enabled = value.$1;
    final delayMs = value.$2;
    wasm.sound_set_looped(_self, enabled, enabled ? delayMs : 0);
  }

  @override
  void unload() {
    // Releases native sound and frees the copied buffer (must stay alive for decoder/buffer lifetime).
    wasm.sound_unload(_self);
    mem.free(_dataPtr);
  }

  @override
  void play() {
    final ok = wasm.sound_play(_self);
    if (ok == 0) {
      throw MiniaudioDartPlatformException("sound_play failed");
    }
  }

  @override
  void replay() {
    final ok = wasm.sound_replay(_self);
    if (ok == 0) {
      throw MiniaudioDartPlatformException("sound_replay failed");
    }
  }

  @override
  void pause() => wasm.sound_pause(_self);
  @override
  void stop() => wasm.sound_stop(_self);
}

final class WebRecorder implements PlatformRecorder {
  WebRecorder(this._self);
  final int _self;
  int _channels = 1;
  int _sampleRate = 48000;

  int get channels => _channels; // expose to higher-level wrapper
  int get sampleRate => _sampleRate; // expose to higher-level wrapper

  @override
  Future<void> initFile(
    String filename, {
    int sampleRate = 48000, // FIX: was 44800
    int channels = 1,
    int format = AudioFormat.float32,
  }) async {
    final result = await wasm.recorder_init_file(
      _self,
      filename,
      sampleRate: sampleRate,
      channels: channels,
      format: format,
    );
    if (result != RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException(
        "Failed to initialize recorder with file. Error code: $result",
      );
    }
    _channels = channels;
    _sampleRate = sampleRate; // track actual
  }

  @override
  Future<void> initStream({
    int sampleRate = 48000, // FIX: was 44800
    int channels = 1,
    int format = AudioFormat.float32,
    int bufferDurationSeconds = 5,
  }) async {
    final result = await wasm.recorder_init_stream(
      _self,
      sampleRate: sampleRate,
      channels: channels,
      format: format,
      bufferDurationSeconds: bufferDurationSeconds,
    );
    if (result != RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException(
        "Failed to initialize recorder stream. Error code: $result",
      );
    }
    _channels = channels;
    _sampleRate = sampleRate; // track actual
  }

  @override
  void start() {
    if (wasm.recorder_start(_self) != RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException("Failed to start recording.");
    }
  }

  @override
  void stop() {
    if (wasm.recorder_stop(_self) != RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException("Failed to stop recording.");
    }
  }

  @override
  int getAvailableFrames() => wasm.recorder_get_available_frames(_self);

  @override
  Float32List getBuffer(int framesToRead, {int channels = 2}) {
    if (framesToRead <= 0) return Float32List(0);
    final ch = _channels;
    final floatsToRead = framesToRead * ch;
    final bytes = floatsToRead * 4;

    final ptr = mem.allocate(bytes);
    try {
      final floatsRead = wasm.recorder_get_buffer(_self, ptr, floatsToRead);
      if (floatsRead <= 0) {
        return Float32List(0);
      }
      return mem.readF32(ptr, floatsRead);
    } finally {
      mem.free(ptr);
    }
  }

  @override
  bool get isRecording => wasm.recorder_is_recording(_self);

  @override
  void dispose() {
    wasm.recorder_destroy(_self);
  }
}

final class WebGenerator implements PlatformGenerator {
  WebGenerator(this._self);
  final int _self;
  int _channels = 1;

  late var _volume = wasm.generator_get_volume(_self);
  @override
  double get volume => _volume;
  @override
  set volume(double value) {
    wasm.generator_set_volume(_self, value);
    _volume = value;
  }

  @override
  Future<void> init(
    int format,
    int channels,
    int sampleRate,
    int bufferDurationSeconds,
  ) async {
    final result = await wasm.generator_init(
      _self,
      format,
      channels,
      sampleRate,
      bufferDurationSeconds,
    );
    if (result != GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException(
        "Failed to initialize generator. Error code: $result",
      );
    }
    _channels = channels;
  }

  @override
  void setWaveform(WaveformType type, double frequency, double amplitude) {
    final result =
        wasm.generator_set_waveform(_self, type.index, frequency, amplitude);
    if (result != GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to set waveform.");
    }
  }

  @override
  void setPulsewave(double frequency, double amplitude, double dutyCycle) {
    final result =
        wasm.generator_set_pulsewave(_self, frequency, amplitude, dutyCycle);
    if (result != GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to set pulse wave.");
    }
  }

  @override
  void setNoise(NoiseType type, int seed, double amplitude) {
    final result = wasm.generator_set_noise(_self, type.index, seed, amplitude);
    if (result != GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to set noise.");
    }
  }

  @override
  void start() {
    final result = wasm.generator_start(_self);
    if (result != GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to start generator.");
    }
  }

  @override
  void stop() {
    final result = wasm.generator_stop(_self);
    if (result != GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to stop generator.");
    }
  }

  @override
  Float32List getBuffer(int framesToRead) {
    final floatsToRead = framesToRead * _channels;
    final ptr = mem.allocate(floatsToRead * 4);
    try {
      final framesRead = wasm.generator_get_buffer(_self, ptr, framesToRead);
      if (framesRead < 0) {
        throw MiniaudioDartPlatformException(
          "Failed to read generator data. Error code: $framesRead",
        );
      }
      return mem.readF32(ptr, framesRead * _channels);
    } finally {
      mem.free(ptr);
    }
  }

  @override
  int getAvailableFrames() => wasm.generator_get_available_frames(_self);

  @override
  void dispose() {
    wasm.generator_destroy(_self);
  }
}
