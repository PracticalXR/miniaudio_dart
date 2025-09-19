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

class MiniaudioDartFfi extends MiniaudioDartPlatformInterface {
  MiniaudioDartFfi();

  @override
  PlatformEngine createEngine() {
    final eng = bindings.engine_alloc();
    if (eng == nullptr) {
      throw MiniaudioDartPlatformOutOfMemoryException();
    }
    return FfiEngine(eng);
  }

  @override
  PlatformRecorder createRecorder() {
    final rec = bindings.recorder_create();
    if (rec == nullptr) {
      throw MiniaudioDartPlatformOutOfMemoryException();
    }
    return FfiRecorder(rec);
  }

  @override
  PlatformGenerator createGenerator() {
    final gen = bindings.generator_create();
    if (gen == nullptr) {
      throw MiniaudioDartPlatformOutOfMemoryException();
    }
    return FfiGenerator(gen);
  }

  @override
  PlatformStreamPlayer createStreamPlayer({
    required PlatformEngine engine,
    required int format,
    required int channels,
    required int sampleRate,
    int bufferMs = 240,
  }) {
    final engWrapper = (engine as FfiEngine)._self;
    final sp = bindings.stream_player_alloc();
    if (sp == nullptr) {
      throw MiniaudioDartPlatformOutOfMemoryException();
    }

    final cfgPtr = calloc<bindings.StreamPlayerConfig>();
    try {
      cfgPtr.ref
        ..formatAsInt = format
        ..channels = channels
        ..sampleRate = sampleRate
        ..bufferMilliseconds = bufferMs
        ..allowCodecPackets = 1 // Always allow codec packets
        ..decodeAccumFrames = 0;

      final ok = bindings.stream_player_init_with_engine(
          sp, engWrapper.cast(), cfgPtr);
      if (ok != 1) {
        bindings.stream_player_free(sp);
        throw MiniaudioDartPlatformException("stream_player_init failed.");
      }
    } finally {
      calloc.free(cfgPtr);
    }

    return FfiStreamPlayer._(sp, channels);
  }

  // Add CrossCoder factory method (standalone)
  @override
  PlatformCrossCoder createCrossCoder() {
    return FfiCrossCoder();
  }
}

// Keep standalone CrossCoder implementation
class FfiCrossCoder implements PlatformCrossCoder {
  Pointer<bindings.CrossCoder>? _self;

  @override
  Future<bool> init(int sampleRate, int channels, int codecId,
      {int application = 2049}) async {
    final cfgPtr = calloc<bindings.CodecConfig>();
    try {
      cfgPtr.ref
        ..sample_rate = sampleRate
        ..channels = channels
        ..bits_per_sample = 32; // Float32

      _self = bindings.crosscoder_create(
          cfgPtr,
          bindings.CodecID.fromValue(codecId),
          application,
          1); // accumulate = true

      final success = _self != nullptr;
      print('CrossCoder created: $_self, success: $success');

      if (success) {
        final frameSize = bindings.crosscoder_frame_size(_self!);
        print('CrossCoder frameSize after creation: $frameSize');
      }

      return success;
    } catch (e) {
      print('CrossCoder init error: $e');
      return false;
    } finally {
      calloc.free(cfgPtr);
    }
  }

  @override
  int get frameSize {
    if (_self == nullptr) {
      print('frameSize called on null CrossCoder');
      return 0;
    }
    final size = bindings.crosscoder_frame_size(_self!);
    return size;
  }

  @override
  (Uint8List packet, int bytesWritten) encodeFrames(Float32List frames) {
    if (_self == nullptr || frames.isEmpty) {
      return (Uint8List(0), 0);
    }

    final channels = 1; // From init
    final expectedFrames = frameSize;
    final expectedSamples = expectedFrames * channels;

    // For PCM passthrough, we might need exact frame count
    if (frames.length != expectedSamples) {
      // For testing, let's pad or truncate
      final adjustedFrames = Float32List(expectedSamples);
      final copyCount =
          frames.length < expectedSamples ? frames.length : expectedSamples;
      for (int i = 0; i < copyCount; i++) {
        adjustedFrames[i] = frames[i];
      }
      return _doEncode(adjustedFrames, expectedFrames);
    }

    return _doEncode(frames, expectedFrames);
  }

  (Uint8List packet, int bytesWritten) _doEncode(
      Float32List frames, int frameCount) {
    final framesPtr = calloc<Float>(frames.length);
    final outPacket = calloc<Uint8>(4096);
    final outBytesPtr = calloc<Int>();

    try {
      // Copy frames to native memory
      for (int i = 0; i < frames.length; i++) {
        framesPtr[i] = frames[i];
      }

      final result = bindings.crosscoder_encode_push_f32(
        _self!,
        framesPtr,
        frameCount,
        outPacket,
        4096,
        outBytesPtr,
      );

      final bytesWritten = outBytesPtr.value;

      if (result > 0 && bytesWritten > 0) {
        final packet = Uint8List.fromList(outPacket.asTypedList(bytesWritten));
        return (packet, bytesWritten);
      }
      return (Uint8List(0), 0);
    } catch (e) {
      print('Encode error: $e');
      return (Uint8List(0), 0);
    } finally {
      calloc.free(framesPtr);
      calloc.free(outPacket);
      calloc.free(outBytesPtr);
    }
  }

  @override
  Float32List decodePacket(Uint8List packet) {
    if (_self == nullptr || packet.isEmpty) return Float32List(0);

    final packetPtr = calloc<Uint8>(packet.length);
    final maxFrames = frameSize * 2; // Give some buffer
    final outFramesPtr = calloc<Float>(maxFrames);

    try {
      // Copy packet to native memory
      for (int i = 0; i < packet.length; i++) {
        packetPtr[i] = packet[i];
      }

      final decodedFrames = bindings.crosscoder_decode_packet(
        _self!,
        packetPtr,
        packet.length,
        outFramesPtr,
        maxFrames,
      );

      print('Decode result: $decodedFrames frames from ${packet.length} bytes');

      if (decodedFrames > 0) {
        return Float32List.fromList(outFramesPtr.asTypedList(decodedFrames));
      }
      return Float32List(0);
    } catch (e) {
      print('Decode error: $e');
      return Float32List(0);
    } finally {
      calloc.free(packetPtr);
      calloc.free(outFramesPtr);
    }
  }

  @override
  void dispose() {
    if (_self != nullptr) {
      bindings.crosscoder_destroy(_self!);
      _self = nullptr;
    }
  }
}

// Update FfiRecorder with codec support
class FfiRecorder implements PlatformRecorder {
  FfiRecorder(Pointer<bindings.Recorder> self) : _self = self;

  final Pointer<bindings.Recorder> _self;
  int _channels = 0;
  RecorderCodecConfig? _codecConfig;

  @override
  Future<void> initStream({
    int sampleRate = 48000,
    int channels = 1,
    int format = AudioFormat.float32,
    int bufferDurationSeconds = 5,
    RecorderCodecConfig? codecConfig,
  }) async {
    final cfgPtr = calloc<bindings.RecorderConfig>();
    final codecCfgPtr =
        codecConfig != null ? calloc<bindings.RecorderCodecConfig>() : nullptr;

    try {
      cfgPtr.ref
        ..sampleRate = sampleRate
        ..channels = channels
        ..formatAsInt = format
        ..bufferDurationSeconds = bufferDurationSeconds
        ..codecConfig = codecCfgPtr
        ..autoStart = 0;

      if (codecConfig != null) {
        codecCfgPtr.ref
          ..codecAsInt = codecConfig.codec.value
          ..opusApplication = codecConfig.opusApplication
          ..opusBitrate = codecConfig.opusBitrate
          ..opusComplexity = codecConfig.opusComplexity
          ..opusVBR = codecConfig.opusVBR ? 1 : 0;
      }

      final ok = bindings.recorder_init(_self, cfgPtr);
      if (ok != 1) {
        throw MiniaudioDartPlatformException("Failed to initialize recorder.");
      }

      _channels = channels;
      _codecConfig = codecConfig;
    } finally {
      calloc.free(cfgPtr);
      if (codecCfgPtr != nullptr) calloc.free(codecCfgPtr);
    }
  }

  @override
  RecorderCodec get codec => _codecConfig?.codec ?? RecorderCodec.pcm;

  @override
  Future<bool> updateCodecConfig(RecorderCodecConfig codecConfig) async {
    final cfgPtr = calloc<bindings.RecorderCodecConfig>();
    try {
      cfgPtr.ref
        ..codecAsInt = codecConfig.codec.value
        ..opusApplication = codecConfig.opusApplication
        ..opusBitrate = codecConfig.opusBitrate
        ..opusComplexity = codecConfig.opusComplexity
        ..opusVBR = codecConfig.opusVBR ? 1 : 0;

      final ok = bindings.recorder_update_codec_config(_self, cfgPtr);
      if (ok == 1) {
        _codecConfig = codecConfig;
        return true;
      }
      return false;
    } finally {
      calloc.free(cfgPtr);
    }
  }

  @override
  dynamic readChunk({int maxFrames = 512}) {
    if (_channels == 0)
      return codec == RecorderCodec.pcm ? Float32List(0) : Uint8List(0);

    final ptrOut = calloc<Pointer<Void>>();
    final framesOut = calloc<Int>();
    try {
      final ok =
          bindings.recorder_acquire_read_region(_self, ptrOut, framesOut);
      if (ok == 0)
        return codec == RecorderCodec.pcm ? Float32List(0) : Uint8List(0);

      final available = framesOut.value;
      if (available <= 0)
        return codec == RecorderCodec.pcm ? Float32List(0) : Uint8List(0);

      final use = available > maxFrames ? maxFrames : available;
      final dataPtr = ptrOut.value;
      if (dataPtr == nullptr)
        return codec == RecorderCodec.pcm ? Float32List(0) : Uint8List(0);

      dynamic result;
      if (codec == RecorderCodec.pcm) {
        // PCM data - return as Float32List
        final floatPtr = dataPtr.cast<Float>();
        final floats = use * _channels;
        result = Float32List.fromList(floatPtr.asTypedList(floats));
      } else {
        // Encoded data - return as Uint8List
        final bytePtr = dataPtr.cast<Uint8>();
        result = Uint8List.fromList(
            bytePtr.asTypedList(use)); // use = bytes in encoded mode
      }

      bindings.recorder_commit_read_frames(_self, use);
      return result;
    } finally {
      calloc.free(ptrOut);
      calloc.free(framesOut);
    }
  }

  @override
  dynamic getBuffer(int framesToRead) => framesToRead <= 0
      ? (codec == RecorderCodec.pcm ? Float32List(0) : Uint8List(0))
      : readChunk(maxFrames: framesToRead);

  @override
  void start() {
    if (_self == nullptr) return;
    final result = bindings.recorder_start(_self);
    if (result != 1) {
      throw MiniaudioDartPlatformException("Failed to start recorder");
    }
  }

  @override
  void stop() {
    if (_self == nullptr) return;
    final result = bindings.recorder_stop(_self);
    if (result != 1) {
      throw MiniaudioDartPlatformException("Failed to stop recorder");
    }
  }

  @override
  bool get isRecording {
    if (_self == nullptr) return false;
    return bindings.recorder_is_recording(_self) == 1;
  }

  @override
  int getAvailableFrames() {
    if (_self == nullptr) return 0;
    return bindings.recorder_get_available_frames(_self);
  }

  double _captureGain = 1.0;
  @override
  double get captureGain {
    if (_self == nullptr) return 1.0;
    return bindings.recorder_get_capture_gain(_self);
  }

  @override
  set captureGain(double value) {
    if (_self == nullptr) return;
    bindings.recorder_set_capture_gain(_self, value);
  }

  @override
  void dispose() => bindings.recorder_destroy(_self);

  @override
  Future<List<(String name, bool isDefault)>> enumerateCaptureDevices() async {
    final ok = bindings.recorder_refresh_capture_devices(_self);
    if (ok != 1) return [];

    final count = bindings.recorder_get_capture_device_count(_self);
    final devices = <(String, bool)>[];

    for (int i = 0; i < count; i++) {
      final namePtr = calloc<Char>(256);
      final isDefaultPtr = calloc<bindings.ma_bool32>();
      try {
        final success = bindings.recorder_get_capture_device_name(
            _self, i, namePtr, 256, isDefaultPtr);
        if (success == 1) {
          final name = namePtr.cast<Utf8>().toDartString();
          final isDefault = isDefaultPtr.value;
          devices.add((name, isDefault as bool));
        }
      } finally {
        calloc.free(namePtr);
        calloc.free(isDefaultPtr);
      }
    }
    return devices;
  }

  @override
  Future<bool> selectCaptureDeviceByIndex(int index) async {
    final ok = bindings.recorder_select_capture_device_by_index(_self, index);
    return ok == 1;
  }

  @override
  int getCaptureDeviceGeneration() =>
      bindings.recorder_get_capture_device_generation(_self);
}

// ================= StreamPlayer, Engine, Sound, Generator =================
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

  @override
  bool pushData(dynamic data) {
    if (data is Float32List) {
      return writeFloat32(data) > 0;
    } else if (data is Uint8List) {
      return pushEncodedPacket(data);
    }
    return false;
  }

  @override
  bool pushEncodedPacket(Uint8List packet) {
    if (packet.isEmpty) return false;
    final ptr = calloc<Uint8>(packet.length);
    try {
      ptr.asTypedList(packet.length).setAll(0, packet);
      final ok = bindings.stream_player_push_encoded_packet(
          _self, ptr.cast(), packet.length);
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
    bindings.stream_player_free(_self);
  }
}

// engine ffi
final class FfiEngine implements PlatformEngine {
  FfiEngine(this._self);
  final Pointer<bindings.Engine> _self;
  bool _disposed = false;

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
