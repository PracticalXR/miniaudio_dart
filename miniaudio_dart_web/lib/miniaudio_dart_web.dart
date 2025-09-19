// ignore_for_file: omit_local_variable_types

import "dart:async";
import "dart:js_interop";
import "dart:typed_data";
import "package:miniaudio_dart_platform_interface/miniaudio_dart_platform_interface.dart";
import "package:miniaudio_dart_web/bindings/memory_web.dart" as mem;
import "package:miniaudio_dart_web/bindings/miniaudio_dart.dart" as wasm;
import "package:web/web.dart" as web;

// Provide the function consumed by the stub import.
MiniaudioDartPlatformInterface registeredInstance() => MiniaudioDartWeb._();

class MiniaudioDartWeb extends MiniaudioDartPlatformInterface {
  MiniaudioDartWeb._();

  static void registerWith(dynamic _) => MiniaudioDartWeb._();

  @override
  PlatformEngine createEngine() {
    final eng = wasm.engine_alloc();
    if (eng == 0) {
      throw MiniaudioDartPlatformOutOfMemoryException();
    }
    return WebEngine(eng);
  }

  @override
  PlatformRecorder createRecorder() {
    final rec = wasm.recorder_create();
    if (rec == 0) {
      throw MiniaudioDartPlatformOutOfMemoryException();
    }
    return WebRecorder(rec);
  }

  @override
  PlatformGenerator createGenerator() {
    final gen = wasm.generator_create();
    if (gen == 0) {
      throw MiniaudioDartPlatformOutOfMemoryException();
    }
    return WebGenerator(gen);
  }

  @override
  PlatformStreamPlayer createStreamPlayer({
    required PlatformEngine engine,
    required int format,
    required int channels,
    required int sampleRate,
    int bufferMs = 240,
  }) {
    final engWrapper = (engine as WebEngine)._self;
    final sp = wasm.stream_player_alloc();
    if (sp == 0) {
      throw MiniaudioDartPlatformOutOfMemoryException();
    }

    // Create StreamPlayerConfig struct (matching FFI)
    final cfgPtr = mem.allocate(28); // sizeof(StreamPlayerConfig)
    try {
      mem.writeI32(cfgPtr, format); // formatAsInt
      mem.writeI32(cfgPtr + 4, channels); // channels
      mem.writeI32(cfgPtr + 8, sampleRate); // sampleRate
      mem.writeI32(cfgPtr + 12, bufferMs); // bufferMilliseconds
      mem.writeI32(cfgPtr + 16, 1); // allowCodecPackets = true
      mem.writeI32(cfgPtr + 20, 0); // decodeAccumFrames = 0

      final ok = wasm.stream_player_init_with_engine(sp, engWrapper, cfgPtr);
      if (ok != 1) {
        wasm.stream_player_free(sp);
        throw MiniaudioDartPlatformException("stream_player_init failed.");
      }
    } finally {
      mem.free(cfgPtr);
    }

    return WebStreamPlayer._(sp, channels);
  }

  @override
  PlatformCrossCoder createCrossCoder() {
    return WebCrossCoder();
  }
}

// Web CrossCoder implementation (matching FFI)
class WebCrossCoder implements PlatformCrossCoder {
  int? _self;
  int _channels = 1;

  @override
  Future<bool> init(int sampleRate, int channels, int codecId,
      {int application = 2049}) async {
    final configPtr = mem.allocate(12); // sizeof(CodecConfig)
    try {
      mem.writeI32(configPtr, sampleRate); // sample_rate
      mem.writeI32(configPtr + 4, channels); // channels
      mem.writeI32(configPtr + 8, 32); // bits_per_sample

      _self = wasm.crosscoder_create(configPtr, codecId, application, 1);
      _channels = channels; // track channels for proper frame count
      return _self != null && _self! != 0;
    } finally {
      mem.free(configPtr);
    }
  }

  @override
  int get frameSize {
    if (_self == null || _self == 0) return 0;
    return wasm.crosscoder_frame_size(_self!);
  }

  @override
  (Uint8List, int) encodeFrames(Float32List frames) {
    if (_self == null || _self == 0 || frames.isEmpty) return (Uint8List(0), 0);

    final framesPtr = mem.allocate(frames.length * 4); // Float32 = 4 bytes
    final outPacketPtr = mem.allocate(4096);
    final outBytesPtr = mem.allocate(4); // for actual bytes written

    try {
      // Copy frames to WASM memory
      final heap = mem.HEAPF32.toDart;
      final offset = framesPtr >> 2; // Float32 offset
      heap.setAll(offset, frames);

      // Pass number of PCM frames (samples / channels), NOT packets
      final frameCount = frames.length ~/ _channels;
      if (frameCount <= 0) return (Uint8List(0), 0);

      final result = wasm.crosscoder_encode_push_f32(
        _self!,
        framesPtr,
        frameCount,
        outPacketPtr,
        4096,
        outBytesPtr,
      );

      final bytesWritten = mem.readI32(outBytesPtr);

      if (result > 0 && bytesWritten > 0) {
        final heapU8 = mem.HEAPU8.toDart;
        final pkt = Uint8List.fromList(
            heapU8.sublist(outPacketPtr, outPacketPtr + bytesWritten));
        return (pkt, bytesWritten);
      }
      return (Uint8List(0), 0);
    } finally {
      mem.free(framesPtr);
      mem.free(outPacketPtr);
      mem.free(outBytesPtr);
    }
  }

  @override
  Float32List decodePacket(Uint8List packet) {
    if (_self == null || _self == 0 || packet.isEmpty) return Float32List(0);

    final packetPtr = mem.allocate(packet.length);
    final outFramesPtr = mem.allocate(4800 * 4); // Max frames * 4 bytes

    try {
      // Copy packet to WASM memory
      final heapU8 = mem.HEAPU8.toDart;
      heapU8.setAll(packetPtr, packet);

      final decodedFrames = wasm.crosscoder_decode_packet(
        _self!,
        packetPtr,
        packet.length,
        outFramesPtr,
        4800,
      );

      if (decodedFrames > 0) {
        return mem.readF32(outFramesPtr, decodedFrames);
      }
      return Float32List(0);
    } finally {
      mem.free(packetPtr);
      mem.free(outFramesPtr);
    }
  }

  @override
  void dispose() {
    if (_self != null && _self! != 0) {
      wasm.crosscoder_destroy(_self!);
      _self = null;
    }
  }
}

// Web StreamPlayer implementation (matching FFI)
final class WebStreamPlayer implements PlatformStreamPlayer {
  WebStreamPlayer._(this._self, this._channels);
  final int _self;
  final int _channels;

  int _scratchPtr = 0;
  int _scratchBytes = 0;

  double _volume = 1.0;
  @override
  double get volume => _volume;
  @override
  set volume(double v) {
    final clamped = (v.isNaN ? 0.0 : v).clamp(0.0, 100.0).toDouble();
    _volume = clamped;
    try {
      wasm.stream_player_set_volume(_self, clamped);
    } catch (_) {}
  }

  @override
  void start() {
    final ok = wasm.stream_player_start(_self);
    if (ok != 1) {
      throw MiniaudioDartPlatformException("stream_player_start failed.");
    }
  }

  @override
  void stop() {
    final ok = wasm.stream_player_stop(_self);
    if (ok != 1) {
      throw MiniaudioDartPlatformException("stream_player_stop failed.");
    }
  }

  @override
  void clear() {
    wasm.stream_player_clear(_self);
  }

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

    if (_scratchBytes < bytes) {
      final newPtr = mem.allocate(bytes);
      if (newPtr == 0) {
        throw MiniaudioDartPlatformOutOfMemoryException();
      }
      if (_scratchPtr != 0) mem.free(_scratchPtr);
      _scratchPtr = newPtr;
      _scratchBytes = bytes;
      assert((_scratchPtr & 3) == 0, "malloc returned unaligned pointer");
    }
    mem.copyFromTypedData(_scratchPtr, interleaved);

    final written =
        wasm.stream_player_write_frames_f32(_self, _scratchPtr, frames);
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
    if (_scratchBytes < packet.length) {
      final newPtr = mem.allocate(packet.length);
      if (newPtr == 0) return false;
      if (_scratchPtr != 0) mem.free(_scratchPtr);
      _scratchPtr = newPtr;
      _scratchBytes = packet.length;
    }
    final heap = mem.HEAPU8.toDart;
    heap.setRange(_scratchPtr, _scratchPtr + packet.length, packet);
    final ok = wasm.stream_player_push_encoded_packet(
        _self, _scratchPtr, packet.length);
    return ok == 1;
  }

  @override
  void dispose() {
    if (_scratchPtr != 0) {
      mem.free(_scratchPtr);
      _scratchPtr = 0;
      _scratchBytes = 0;
    }
    wasm.stream_player_uninit(_self);
    wasm.stream_player_free(_self);
  }
}

// Web Recorder implementation (matching FFI)
class WebRecorder implements PlatformRecorder {
  WebRecorder(this._self);
  final int _self;
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
    final cfgPtr = mem.allocate(28); // sizeof(RecorderConfig)
    final codecCfgPtr = codecConfig != null ? mem.allocate(20) : 0;

    try {
      // Fill RecorderConfig struct
      mem.writeI32(cfgPtr, sampleRate); // sampleRate
      mem.writeI32(cfgPtr + 4, channels); // channels
      mem.writeI32(cfgPtr + 8, format); // formatAsInt
      mem.writeI32(cfgPtr + 12, bufferDurationSeconds); // bufferDurationSeconds
      mem.writeI32(cfgPtr + 16, codecCfgPtr); // codecConfig pointer
      mem.writeI32(cfgPtr + 20, 0); // autoStart = false

      // Fill codec config if provided
      if (codecConfig != null && codecCfgPtr != 0) {
        mem.writeI32(codecCfgPtr, codecConfig.codec.value); // codecAsInt
        mem.writeI32(codecCfgPtr + 4, codecConfig.opusApplication);
        mem.writeI32(codecCfgPtr + 8, codecConfig.opusBitrate);
        mem.writeI32(codecCfgPtr + 12, codecConfig.opusComplexity);
        mem.writeI32(codecCfgPtr + 16, codecConfig.opusVBR ? 1 : 0);
      }

      final ok = await wasm.recorder_init(_self, cfgPtr);
      if (ok != 1) {
        throw MiniaudioDartPlatformException("Failed to initialize recorder.");
      }

      _channels = channels;
      _codecConfig = codecConfig;
    } finally {
      mem.free(cfgPtr);
      if (codecCfgPtr != 0) mem.free(codecCfgPtr);
    }
  }

  @override
  RecorderCodec get codec => _codecConfig?.codec ?? RecorderCodec.pcm;

  @override
  Future<bool> updateCodecConfig(RecorderCodecConfig codecConfig) async {
    // Not implemented in web yet
    return false;
  }

  @override
  dynamic readChunk({int maxFrames = 512}) {
    if (_channels == 0) {
      return codec == RecorderCodec.pcm ? Float32List(0) : Uint8List(0);
    }

    final ptrOut = mem.allocate(4);
    final framesOut = mem.allocate(4);
    try {
      final ok = wasm.recorder_acquire_read_region(_self, ptrOut, framesOut);
      if (ok == 0) {
        return codec == RecorderCodec.pcm ? Float32List(0) : Uint8List(0);
      }

      final available = mem.readI32(framesOut);
      if (available <= 0) {
        return codec == RecorderCodec.pcm ? Float32List(0) : Uint8List(0);
      }

      final use = available > maxFrames ? maxFrames : available;
      final dataPtr = mem.readI32(ptrOut);
      if (dataPtr == 0) {
        return codec == RecorderCodec.pcm ? Float32List(0) : Uint8List(0);
      }

      dynamic result;
      if (codec == RecorderCodec.pcm) {
        // PCM data - return as Float32List
        final floats = use * _channels;
        result = mem.readF32(dataPtr, floats);
      } else {
        // Encoded data - return as Uint8List
        final heapU8 = mem.HEAPU8.toDart;
        result = Uint8List.fromList(heapU8.sublist(dataPtr, dataPtr + use));
      }

      wasm.recorder_commit_read_frames(_self, use);
      return result;
    } finally {
      mem.free(ptrOut);
      mem.free(framesOut);
    }
  }

  @override
  dynamic getBuffer(int framesToRead) => framesToRead <= 0
      ? (codec == RecorderCodec.pcm ? Float32List(0) : Uint8List(0))
      : readChunk(maxFrames: framesToRead);

  @override
  void start() {
    final result = wasm.recorder_start(_self);
    if (result != 1) {
      throw MiniaudioDartPlatformException("Failed to start recorder");
    }
  }

  @override
  void stop() {
    final result = wasm.recorder_stop(_self);
    if (result != 1) {
      throw MiniaudioDartPlatformException("Failed to stop recorder");
    }
  }

  @override
  bool get isRecording => wasm.recorder_is_recording(_self) == 1;

  @override
  int getAvailableFrames() => wasm.recorder_get_available_frames(_self);

  double _captureGain = 1.0;
  @override
  double get captureGain => _captureGain;
  @override
  set captureGain(double value) {
    _captureGain = value;
    // Web implementation would call wasm function if available
  }

  @override
  void dispose() => wasm.recorder_destroy(_self);

  @override
  Future<List<(String name, bool isDefault)>> enumerateCaptureDevices() async =>
      [("Default Input", true)];

  @override
  Future<bool> selectCaptureDeviceByIndex(int index) async => index == 0;

  @override
  int getCaptureDeviceGeneration() => 0;
}

// Web Engine implementation (matching FFI)
final class WebEngine implements PlatformEngine {
  WebEngine(this._self);
  final int _self;

  @override
  EngineState state = EngineState.uninit;
  Future<void>? _initPending;
  int _playbackGen = 0;

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
      // Try to resume AudioContext first (Web requirement)
      try {
        await web.window.navigator.mediaDevices
            .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
            .toDart;
      } catch (e) {
        // Continue anyway - getUserMedia might not be needed for playback
      }

      final ok = await wasm.engine_init(_self, periodMs);
      if (ok != 1) {
        throw MiniaudioDartPlatformException('Failed to init the engine.');
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
    wasm.engine_free(_self);
  }

  @override
  void start() {
    final pending = _initPending;
    if (pending != null) {
      pending.whenComplete(() {
        final result = wasm.engine_start(_self);
        if (result != 1) {
          throw MiniaudioDartPlatformException("Failed to start the engine.");
        }
      });
      return;
    }
    final result = wasm.engine_start(_self);
    if (result != 1) {
      throw MiniaudioDartPlatformException("Failed to start the engine.");
    }
  }

  @override
  Future<PlatformSound> loadSound(AudioData audioData) async {
    if (_initPending != null) {
      await _initPending;
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
        throw MiniaudioDartPlatformException("Failed to allocate a sound.");
      }

      final result = wasm.engine_load_sound(
        _self,
        sound,
        dataPtr,
        bytes,
        audioData.format,
        audioData.sampleRate,
        audioData.channels,
      );
      if (result != 1) {
        wasm.sound_unload(sound);
        mem.free(dataPtr);
        throw MiniaudioDartPlatformException("Failed to load a sound.");
      }

      return WebSound._fromPtrs(sound, dataPtr);
    } catch (e) {
      mem.free(dataPtr);
      rethrow;
    }
  }

  @override
  Future<List<(String name, bool isDefault)>> enumeratePlaybackDevices() async {
    _playbackGen++;
    return [("Default Output", true)];
  }

  @override
  Future<bool> selectPlaybackDeviceByIndex(int index) async {
    _playbackGen++;
    return index == 0;
  }

  @override
  int getPlaybackDeviceGeneration() => _playbackGen;
}

// Web Sound implementation (matching FFI)
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
    wasm.sound_unload(_self);
    mem.free(_dataPtr);
  }

  @override
  void play() {
    final ok = wasm.sound_play(_self);
    if (ok != 1) {
      throw MiniaudioDartPlatformException("Failed to play the sound.");
    }
  }

  @override
  void replay() {
    final ok = wasm.sound_replay(_self);
    if (ok != 1) {
      throw MiniaudioDartPlatformException("Failed to replay the sound.");
    }
  }

  @override
  void pause() => wasm.sound_pause(_self);
  @override
  void stop() => wasm.sound_stop(_self);

  @override
  bool rebindToEngine(PlatformEngine engine) {
    // Web: no real device switch; keep playing.
    return true;
  }
}

// Web Generator implementation (matching FFI)
class WebGenerator implements PlatformGenerator {
  WebGenerator(this._self);
  final int _self;

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
    final ptr = mem.allocate(framesToRead * 4); // Float32 = 4 bytes
    try {
      final framesRead = wasm.generator_get_buffer(_self, ptr, framesToRead);
      if (framesRead < 0) {
        throw MiniaudioDartPlatformException(
          "Failed to get generator buffer. Error code: $framesRead",
        );
      }
      return mem.readF32(ptr, framesRead);
    } finally {
      mem.free(ptr);
    }
  }

  @override
  int getAvailableFrames() => wasm.generator_get_available_frames(_self);

  @override
  void dispose() => wasm.generator_destroy(_self);
}
