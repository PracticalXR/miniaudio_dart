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

  // streaming player
  @override
  PlatformStreamPlayer createStreamPlayer({
    required PlatformEngine engine,
    required int format,
    required int channels,
    required int sampleRate,
    int bufferMs = 240,
  }) {
    final eng = (engine as FfiEngine)._self;

    final sp = bindings.stream_player_alloc();
    if (sp == nullptr) {
      throw MiniaudioDartPlatformOutOfMemoryException();
    }

    final ok = bindings.stream_player_init_with_engine(
      sp,
      eng,
      bindings.ma_format.fromValue(format),
      channels,
      sampleRate,
      bufferMs,
    );
    if (ok != 1) {
      // Do not free sp with calloc; it was allocated in C (ma_malloc).
      // Optional: add a native stream_player_free() and call it here.
      throw MiniaudioDartPlatformException("stream_player_init failed.");
    }

    return FfiStreamPlayer._(sp, channels);
  }
}

final class FfiStreamPlayer implements PlatformStreamPlayer {
  FfiStreamPlayer._(Pointer<bindings.StreamPlayer> self, this._channels)
      : _self = self;

  final Pointer<bindings.StreamPlayer> _self;
  final int _channels;

  Pointer<Float> _scratch = nullptr;
  int _scratchFloats = 0;

  double _volume = 1.0;
  @override
  double get volume => _volume;

  @override
  set volume(double v) {
    final clamped = v.isNaN ? 0.0 : v.clamp(0.0, 100.0).toDouble();
    _volume = clamped;
    bindings.stream_player_set_volume(_self, clamped);
  }

  @override
  void start() {
    final ok = bindings.stream_player_start(_self);
    if (ok != 1) {
      throw MiniaudioDartPlatformException("stream_player_start failed.");
    }
  }

  @override
  void stop() {
    final ok = bindings.stream_player_stop(_self);
    if (ok != 1) {
      throw MiniaudioDartPlatformException("stream_player_stop failed.");
    }
  }

  @override
  void clear() {
    bindings.stream_player_clear(_self);
  }

  // Safely writes interleaved Float32 samples. Returns frames written by native side.
  @override
  int writeFloat32(Float32List interleaved) {
    if (interleaved.isEmpty) return 0;
    final int floats = interleaved.length;
    if (floats % _channels != 0) {
      throw MiniaudioDartPlatformException(
        "writeFloat32: floats ($floats) not divisible by channels ($_channels)",
      );
    }
    final int frames = floats ~/ _channels;

    if (_scratch == nullptr || _scratchFloats < floats) {
      if (_scratch != nullptr) calloc.free(_scratch);
      _scratch = calloc<Float>(floats);
      _scratchFloats = floats;
    }
    _scratch.asTypedList(floats).setAll(0, interleaved);

    final int written = bindings.stream_player_write_frames_f32(
      _self,
      _scratch,
      frames,
    );
    return written;
  }

  // push encoded packet (Opus/PCM framed)
  @override
  bool pushEncodedPacket(Uint8List packet) {
    if (packet.isEmpty) return false;
    final ptr = calloc<Uint8>(packet.length);
    try {
      ptr.asTypedList(packet.length).setAll(0, packet);
      final ok = bindings.stream_player_push_encoded_packet(
        _self,
        ptr.cast(),
        packet.length,
      );
      return ok == 1;
    } finally {
      calloc.free(ptr);
    }
  }

  @override
  void dispose() {
    if (_scratch != nullptr) {
      calloc.free(_scratch);
      _scratch = nullptr;
      _scratchFloats = 0;
    }
    bindings.stream_player_uninit(_self);
    bindings.stream_player_free(_self);
  }
}

// engine ffi
final class FfiEngine implements PlatformEngine {
  FfiEngine(this._self);
  final Pointer<bindings.Engine> _self;
  bool _disposed = false;

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
    if (_disposed) return;
    bindings.engine_uninit(_self);
    bindings.engine_free(_self); // correct native free
    _disposed = true;
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

  Future<List<(String name, bool isDefault)>> enumeratePlaybackDevices() async {
    // Refresh native cache
    bindings.engine_refresh_playback_devices(_self);
    final count = bindings.engine_get_playback_device_count(_self);
    final results = <(String, bool)>[];
    if (count == 0) return results;
    // Temporary buffer for names
    const cap = 256;
    final nameBuf = calloc<Int8>(cap);
    final isDefaultPtr = calloc<Uint8>();
    try {
      for (var i = 0; i < count; i++) {
        final ok = bindings.engine_get_playback_device_name(
          _self,
          i,
          nameBuf.cast(),
          cap,
          isDefaultPtr.cast(),
        );
        if (ok == 0) continue;
        final name = nameBuf.cast<Utf8>().toDartString();
        final isDef = isDefaultPtr.value != 0;
        results.add((name, isDef));
      }
    } finally {
      calloc.free(nameBuf);
      calloc.free(isDefaultPtr);
    }
    return results;
  }

  Future<bool> selectPlaybackDeviceByIndex(int index) async {
    // IMPORTANT: Existing Sound / StreamPlayer objects tied to previous engine
    // must be recreated after a successful switch.
    final ok = bindings.engine_select_playback_device_by_index(_self, index);
    return ok != 0;
  }

  @override
  int getPlaybackDeviceGeneration() =>
      bindings.engine_get_playback_device_generation(_self);

  Pointer<bindings.ma_engine> get _maEngine =>
      bindings.engine_get_ma_engine(_self);
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
    if (_data != nullptr) {
      calloc.free(_data); // only the temporary PCM copy
    }
    bindings.sound_free(_self); // NEW
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

  @override
  bool rebindToEngine(PlatformEngine engine) {
    if (engine is! FfiEngine) return false;
    final nativeMaEngine = engine._maEngine; // Pointer<ma_engine>
    final res = bindings.sound_rebind_engine(_self, nativeMaEngine);
    return res == 1;
  }
}

// recorder ffi
class FfiRecorder implements PlatformRecorder {
  FfiRecorder(Pointer<bindings.Recorder> self) : _self = self;

  final Pointer<bindings.Recorder> _self;

  int _channels = 0;
  int _sampleRate = 0;

  bool _opusEnabled = false;

  @override
  Future<void> initFile(
    String filename, {
    int sampleRate = 48000,
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
      _channels = channels;
      _sampleRate = sampleRate;
    } finally {
      calloc.free(filenamePtr);
    }
  }

  @override
  Future<void> initStream({
    int sampleRate = 48000,
    int channels = 1,
    int format = AudioFormat.float32,
    int bufferDurationSeconds = 5,
  }) async {
    final res = bindings.recorder_init_stream(
      _self,
      sampleRate,
      channels,
      bindings.ma_format.fromValue(format),
      bufferDurationSeconds,
    );
    if (res != bindings.RecorderResult.RECORDER_OK) {
      print("res=$res");
      throw MiniaudioDartPlatformException(
        "Failed to initialize recorder stream.",
      );
    }
    _channels = channels;
    _sampleRate = sampleRate;
  }

  @override
  Float32List readChunk({int maxFrames = 512}) {
    if (_channels == 0) return Float32List(0);
    // Allocate native-sized pointer holder (address) and native int for frames.
    final ptrOut = calloc<UintPtr>(); // pointer-sized integer
    final framesOut = calloc<Int>(); // matches C 'int *'
    try {
      final ok = bindings.recorder_acquire_read_region(
        _self,
        ptrOut,
        framesOut,
      );
      if (ok == 0) {
        return Float32List(0);
      }
      final framesAvail = framesOut.value;
      if (framesAvail <= 0) return Float32List(0);

      final use = framesAvail > maxFrames ? maxFrames : framesAvail;
      final addr = ptrOut.value;
      if (addr == 0) return Float32List(0);

      final floats = use * _channels;
      final data = Float32List.fromList(
        Pointer<Float>.fromAddress(addr).asTypedList(floats),
      );

      bindings.recorder_commit_read_frames(_self, use);
      return data;
    } finally {
      calloc.free(ptrOut);
      calloc.free(framesOut);
    }
  }

  @override
  Float32List getBuffer(int framesToRead) {
    // delegate to readChunk for consistency
    if (framesToRead <= 0) return Float32List(0);
    return readChunk(maxFrames: framesToRead);
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

  @override
  int getAvailableFrames() => bindings.recorder_get_available_frames(_self);

  @override
  void dispose() => bindings.recorder_destroy(_self);

  @override
  Future<List<(String name, bool isDefault)>> enumerateCaptureDevices() async {
    bindings.recorder_refresh_capture_devices(_self);
    final count = bindings.recorder_get_capture_device_count(_self);
    final out = <(String, bool)>[];
    if (count == 0) return out;
    final nameBuf = calloc<Int8>(256);
    final defPtr = calloc<Uint8>();
    try {
      for (var i = 0; i < count; i++) {
        final ok = bindings.recorder_get_capture_device_name(
          _self,
          i,
          nameBuf.cast(),
          256,
          defPtr.cast(),
        );
        if (ok == 0) continue;
        final name = nameBuf.cast<Utf8>().toDartString();
        final isDef = defPtr.value != 0;
        out.add((name, isDef));
      }
    } finally {
      calloc.free(nameBuf);
      calloc.free(defPtr);
    }
    return out;
  }

  @override
  Future<bool> selectCaptureDeviceByIndex(int index) async {
    final ok = bindings.recorder_select_capture_device_by_index(_self, index);
    return ok == 1;
  }

  @override
  int getCaptureDeviceGeneration() =>
      bindings.recorder_get_capture_device_generation(_self);

  @override
  Future<bool> enableOpusEncoding({
    int targetBitrate = 64000,
    bool vbr = true,
    int complexity = 5,
    bool fec = false,
    int expectedPacketLossPercent = 0,
    bool dtx = false,
  }) async {
    if (_opusEnabled) return true;
    final ok =
        bindings.recorder_attach_inline_opus(_self, _sampleRate, _channels);
    if (ok == 1) {
      _opusEnabled = true;
      // Optional: apply controls if you expose them:
      // bindings.recorder_opus_set_bitrate(_self, targetBitrate);
      return true;
    }
    return false;
  }

  @override
  int encodedPacketCount() {
    if (!_opusEnabled) return 0;
    return bindings.recorder_encoder_pending(_self);
  }

  @override
  Uint8List dequeueEncodedPacket({int maxPacketBytes = 1500}) {
    if (!_opusEnabled) return Uint8List(0);
    final ptr = calloc<Uint8>(maxPacketBytes);
    try {
      final len = bindings.recorder_encoder_dequeue_packet(
          _self, ptr.cast(), maxPacketBytes);
      if (len <= 0) return Uint8List(0);
      return Uint8List.fromList(ptr.asTypedList(len));
    } finally {
      calloc.free(ptr);
    }
  }

  int pushInlineEncoderFloat32(Float32List frames) {
    if (frames.isEmpty || !_opusEnabled) return 0;
    final int channels = _channels;
    if (frames.length % channels != 0) {
      throw MiniaudioDartPlatformException(
          "Frame count not divisible by channels");
    }
    final frameCount = frames.length ~/ channels;
    final ptr = calloc<Float>(frames.length);
    try {
      ptr.asTypedList(frames.length).setAll(0, frames);
      return bindings.recorder_inline_encoder_feed_f32(_self, ptr, frameCount);
    } finally {
      calloc.free(ptr);
    }
  }

  bool flushInlineEncoder({bool padWithZeros = true}) {
    if (!_opusEnabled) return false;
    final r =
        bindings.recorder_inline_encoder_flush(_self, padWithZeros ? 1 : 0);
    return r == 1;
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
  Future<void> init(
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
