// ignore_for_file: omit_local_variable_types

import "dart:ffi";
import "dart:typed_data";

import "package:ffi/ffi.dart";
import "package:miniaudio_dart_ffi/miniaudio_dart_ffi_bindings.dart"
    as bindings;
import "package:miniaudio_dart_platform_interface/miniaudio_dart_platform_interface.dart";

// dynamic lib
const String _libName = "miniaudio_dart_ffi";

MiniaudioDartPlatformInterface registeredInstance() => MiniaudioDartFfi();

// miniaudio_dart ffi
class MiniaudioDartFfi extends MiniaudioDartPlatformInterface {
  MiniaudioDartFfi();

  @override
  PlatformEngine createEngine() {
    final self = bindings.engine_alloc();
    if (self == nullptr) throw MiniaudioDartPlatformOutOfMemoryException();
    return FfiEngine(self);
  }

  @override
  PlatformRecorder createRecorder() {
    final self = bindings.recorder_create();
    if (self == nullptr) throw MiniaudioDartPlatformOutOfMemoryException();
    return FfiRecorder(self);
  }

  @override
  PlatformGenerator createGenerator() {
    final self = bindings.generator_create();
    if (self == nullptr) throw MiniaudioDartPlatformOutOfMemoryException();
    return FfiGenerator(self);
  }
}

// engine ffi
final class FfiEngine implements PlatformEngine {
  FfiEngine(Pointer<bindings.Engine> self) : _self = self;

  final Pointer<bindings.Engine> _self;

  @override
  EngineState state = EngineState.uninit;

  @override
  Future<void> init(int periodMs) async {
    if (bindings.engine_init(_self, periodMs) != 1) {
      throw MiniaudioDartPlatformException("Failed to init the engine.");
    }
  }

  @override
  void dispose() {
    bindings.engine_uninit(_self);
    calloc.free(_self);
  }

  @override
  void start() {
    if (bindings.engine_start(_self) != 1) {
      throw MiniaudioDartPlatformException("Failed to start the engine.");
    }
  }

  @override
  Future<PlatformSound> loadSound(AudioData audioData) async {
    // Allocate exact number of float samples (elements), not bytes.
    final int sampleCount = audioData.buffer.length;
    final Pointer<Float> dataPtr = calloc<Float>(sampleCount);
    // Copy PCM into native buffer.
    dataPtr.asTypedList(sampleCount).setAll(0, audioData.buffer);
    // Size in bytes for the native API (if it expects bytes).
    final int dataSize = sampleCount * sizeOf<Float>();
    final Pointer<bindings.Sound> sound = bindings.sound_alloc();
    if (sound == nullptr) {
      calloc.free(dataPtr);
      throw MiniaudioDartPlatformException("Failed to allocate a sound.");
    }

    final int maFormat = audioData.format;
    final int result = bindings.engine_load_sound(
      _self,
      sound,
      dataPtr,
      dataSize,
      bindings.ma_format.fromValue(maFormat),
      audioData.sampleRate,
      audioData.channels,
    );

    if (result != 1) {
      bindings.sound_unload(sound);
      calloc.free(dataPtr); // avoid leak on failure
      throw MiniaudioDartPlatformException("Failed to load a sound.");
    }

    return FfiSound._fromPtrs(sound, dataPtr);
  }
}

// sound ffi
final class FfiSound implements PlatformSound {
  FfiSound._fromPtrs(Pointer<bindings.Sound> self, Pointer data)
      : _self = self,
        _data = data,
        _volume = bindings.sound_get_volume(self),
        _duration = bindings.sound_get_duration(self);

  final Pointer<bindings.Sound> _self;
  final Pointer _data;

  double _volume;
  @override
  double get volume => _volume;
  @override
  set volume(double value) {
    bindings.sound_set_volume(_self, value);
    _volume = value;
  }

  final double _duration;
  @override
  double get duration => _duration;

  PlatformSoundLooping _looping = (false, 0);
  @override
  PlatformSoundLooping get looping => _looping;
  @override
  set looping(PlatformSoundLooping value) {
    bindings.sound_set_looped(_self, value.$1, value.$2);
    _looping = value;
  }

  @override
  void unload() {
    bindings.sound_unload(_self);
    calloc.free(_data);
  }

  @override
  void play() {
    if (bindings.sound_play(_self) != 1) {
      throw MiniaudioDartPlatformException("Failed to play the sound.");
    }
  }

  @override
  void replay() {
    bindings.sound_replay(_self);
  }

  @override
  void pause() => bindings.sound_pause(_self);
  @override
  void stop() => bindings.sound_stop(_self);
}

// recorder ffi
class FfiRecorder implements PlatformRecorder {
  FfiRecorder(Pointer<bindings.Recorder> self) : _self = self;

  final Pointer<bindings.Recorder> _self;

  @override
  Future<void> initFile(
    String filename, {
    int sampleRate = 44800,
    int channels = 1,
    int format = 4,
  }) async {
    final filenamePtr = filename.toNativeUtf8();
    try {
      if (bindings.recorder_init_file(
            _self,
            filenamePtr.cast(),
            sampleRate,
            channels,
            bindings.ma_format.fromValue(format),
          ) !=
          bindings.RecorderResult.RECORDER_OK) {
        throw MiniaudioDartPlatformException(
          "Failed to initialize recorder with file.",
        );
      }
    } finally {
      calloc.free(filenamePtr);
    }
  }

  @override
  Future<void> initStream({
    int sampleRate = 44800,
    int channels = 1,
    int format = 4, // float32
    int bufferDurationSeconds = 5,
  }) async {
    if (bindings.recorder_init_stream(
          _self,
          sampleRate,
          channels,
          bindings.ma_format.fromValue(format),
          bufferDurationSeconds,
        ) !=
        bindings.RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException(
        "Failed to initialize recorder stream.",
      );
    }
  }

  @override
  void start() {
    if (bindings.recorder_start(_self) != bindings.RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException("Failed to start recording.");
    }
  }

  @override
  void stop() {
    if (bindings.recorder_stop(_self) != bindings.RecorderResult.RECORDER_OK) {
      throw MiniaudioDartPlatformException("Failed to stop recording.");
    }
  }

  @override
  bool get isRecording => bindings.recorder_is_recording(_self);

  Pointer<Float> bufferPtr = calloc.allocate<Float>(0);

  @override
  Float32List getBuffer(int framesToRead) {
    // framesToRead is interpreted by the native side; the third argument is a count,
    // not bytes. Allocate that many float elements and free after copying.
    final int requested =
        framesToRead; // native may treat this as frames or samples
    final Pointer<Float> ptr = calloc<Float>(requested);
    final int read = bindings.recorder_get_buffer(_self, ptr, requested);
    if (read < 0) {
      calloc.free(ptr);
      throw MiniaudioDartPlatformException(
        "Failed to get recorder buffer. Error code: $read",
      );
    }
    // Copy out so we can free native memory immediately.
    final out = Float32List.fromList(ptr.asTypedList(read));
    calloc.free(ptr);
    return out;
  }

  @override
  int getAvailableFrames() => bindings.recorder_get_available_frames(_self);

  @override
  void dispose() {
    bindings.recorder_destroy(_self);
  }
}

// generator ffi
class FfiGenerator implements PlatformGenerator {
  FfiGenerator(Pointer<bindings.Generator> self)
      : _self = self,
        _volume = bindings.generator_get_volume(self);

  final Pointer<bindings.Generator> _self;

  double _volume;
  @override
  double get volume => _volume;
  @override
  set volume(double value) {
    bindings.generator_set_volume(_self, value);
    _volume = value;
  }

  @override
  Future<int> init(
    int format,
    int channels,
    int sampleRate,
    int bufferDurationSeconds,
  ) async {
    final result = bindings.generator_init(
      _self,
      bindings.ma_format.fromValue(format),
      channels,
      sampleRate,
      bufferDurationSeconds,
    );
    if (result != bindings.GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException(
        "Failed to initialize generator. Error code: $result",
      );
    }
    return result.value;
  }

  @override
  void setWaveform(WaveformType type, double frequency, double amplitude) {
    final result = bindings.generator_set_waveform(
      _self,
      bindings.ma_waveform_type.fromValue(type.index),
      frequency,
      amplitude,
    );
    if (result != bindings.GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to set waveform.");
    }
  }

  @override
  void setPulsewave(double frequency, double amplitude, double dutyCycle) {
    final result = bindings.generator_set_pulsewave(
      _self,
      frequency,
      amplitude,
      dutyCycle,
    );
    if (result != bindings.GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to set pulse wave.");
    }
  }

  @override
  void setNoise(NoiseType type, int seed, double amplitude) {
    final result = bindings.generator_set_noise(
      _self,
      bindings.ma_noise_type.fromValue(type.index),
      seed,
      amplitude,
    );
    if (result != bindings.GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to set noise.");
    }
  }

  @override
  void start() {
    final result = bindings.generator_start(_self);
    if (result != bindings.GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to start generator.");
    }
  }

  @override
  void stop() {
    final result = bindings.generator_stop(_self);
    if (result != bindings.GeneratorResult.GENERATOR_OK) {
      throw MiniaudioDartPlatformException("Failed to stop generator.");
    }
  }

  Pointer<Float> bufferPtr = calloc.allocate<Float>(0);

  @override
  Float32List getBuffer(int framesToRead) {
    // Same as recorder: counts are elements, not bytes.
    final int requested = framesToRead;
    final Pointer<Float> ptr = calloc<Float>(requested);
    final int read = bindings.generator_get_buffer(_self, ptr, requested);
    if (read < 0) {
      calloc.free(ptr);
      throw MiniaudioDartPlatformException(
        "Failed to get generator buffer. Error code: $read",
      );
    }
    final out = Float32List.fromList(ptr.asTypedList(read));
    calloc.free(ptr);
    return out;
  }

  @override
  int getAvailableFrames() => bindings.generator_get_available_frames(_self);

  @override
  void dispose() {
    bindings.generator_destroy(_self);
  }
}
