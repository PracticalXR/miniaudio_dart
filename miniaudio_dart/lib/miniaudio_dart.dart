import "dart:typed_data";

import "package:miniaudio_dart_platform_interface/miniaudio_dart_platform_interface.dart";
export "package:miniaudio_dart_platform_interface/miniaudio_dart_platform_interface.dart"
    show
        AudioData,
        AudioFormat,
        MiniaudioDartPlatformException,
        MiniaudioDartPlatformOutOfMemoryException,
        NoiseType,
        WaveformType;

/// Controls the loading and unloading of `Sound`s.
///
/// Should be initialized before doing anything.
/// Should be started to hear any sound.
final class Engine {
  bool isInit = false;
  Engine() {
    _finalizer.attach(this, _engine);
  }

  static final _finalizer = Finalizer<PlatformEngine>(
    (engine) => engine.dispose(),
  );
  static final _soundsFinalizer = Finalizer<Sound>((sound) => sound.unload());

  final _engine = PlatformEngine();
  final _loadedSounds = <Sound>[];

  /// Initializes an engine.
  ///
  /// Change an update period (affects the sound latency).
  Future<void> init([int periodMs = 10]) async {
    if (isInit) throw EngineAlreadyInitError();

    await _engine.init(periodMs);
    isInit = true;
  }

  /// Starts an engine.
  Future<void> start() async => _engine.start();

  /// Copies `data` to the internal memory location and creates a `Sound` from it.
  Future<Sound> loadSound(AudioData audioData) async {
    final engineSound = await _engine.loadSound(audioData);
    final sound = Sound._(engineSound);
    _loadedSounds.add(sound);
    _soundsFinalizer.attach(this, sound, detach: sound);
    return sound;
  }

  /// Enumerate playback devices. Returns (name, isDefault).
  Future<List<(String, bool)>> enumeratePlaybackDevices() =>
      _engine.enumeratePlaybackDevices();

  /// Select playback device by index (recreates native engine).
  Future<bool> selectPlaybackDeviceByIndex(int index) =>
      _engine.selectPlaybackDeviceByIndex(index);

  /// Convenience: stop engine, switch device, restart.
  Future<bool> switchPlaybackDevice(int index) async {
    if (!isInit) return false;
    try {
      // Caller should have disposed sounds/stream players first.
      await start(); // ensures engine started (no-op if already)
      // Stop before swap (platform engine handles internally if needed).
      final ok = await selectPlaybackDeviceByIndex(index);
      if (!ok) return false;
      // Restart if needed.
      await start();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Switch playback device AND rebuild loaded sounds & stream players.
  /// Generators & StreamPlayers are disposed and recreated (simpler & safe).
  Future<bool> switchPlaybackDeviceAndRebuild(
    int index, {
    List<StreamPlayer>? streamPlayers,
    List<Generator>? generators,
  }) async {
    if (!isInit) return false;

    final soundsToRebind = List<Sound>.from(_loadedSounds);

    for (final s in soundsToRebind) {
      try {
        s.pause();
      } catch (_) {}
    }
    streamPlayers?.forEach((sp) {
      try {
        sp.stop();
      } catch (_) {}
    });
    generators?.forEach((g) {
      try {
        g.stop();
      } catch (_) {}
    });

    final ok = await selectPlaybackDeviceByIndex(index);
    if (!ok) return false;

    for (final s in soundsToRebind) {
      s._rebindAfterDeviceChange(this);
    }

    // StreamPlayers / Generators: simplest is caller recreates; skip snapshot complexity
    return true;
  }

  /// Polls playback device generation and emits updated device lists.
  /// Caller listens to the stream for hot device changes.
  Stream<List<(String, bool)>> playbackDeviceChanges({
    Duration interval = const Duration(seconds: 1),
  }) async* {
    var lastGen = -1;
    while (true) {
      await Future.delayed(interval);
      if (!isInit) continue;
      final gen = _engine.getPlaybackDeviceGeneration();
      if (gen != lastGen) {
        lastGen = gen;
        try {
          final list = await _engine.enumeratePlaybackDevices();
          yield list;
        } catch (_) {
          // swallow errors; continue polling
        }
      }
    }
  }

  /// Switch playback device while keeping an optional recorder running.
  /// If [monitorPlayer] provided, it is rebuilt (preserving basic params & volume).
  /// Recorder keeps running; only monitoring is briefly interrupted.
  Future<bool> switchPlaybackDevicePreservingMonitoring({
    required int index,
    Recorder? recorder,
    StreamPlayer? monitorPlayer,
    bool rebindSounds = true,
  }) async {
    if (!isInit) return false;

    // Snapshot monitor state
    double? monitorVolume;
    bool monitorWasStarted = false;
    int? monChannels, monRate, monBufferMs;
    if (monitorPlayer != null && monitorPlayer.isInit) {
      monitorVolume = monitorPlayer.volume;
      monitorWasStarted = monitorPlayer.isInit;
      monChannels = monitorPlayer._channels;
      monRate = monitorPlayer._sampleRate;
      monBufferMs = monitorPlayer._bufferMs;
      try {
        monitorPlayer.stop();
      } catch (_) {}
    }

    // (Optional) pause sounds before switch to avoid glitches
    List<Sound> pausedSounds = [];
    if (rebindSounds) {
      pausedSounds = List<Sound>.from(_loadedSounds);
      for (final s in pausedSounds) {
        try {
          s.pause();
        } catch (_) {}
      }
    }

    final ok = await selectPlaybackDeviceByIndex(index);
    if (!ok) {
      // Try to resume monitor if selection failed
      if (monitorPlayer != null && monitorPlayer.isInit && monitorWasStarted) {
        try {
          monitorPlayer.start();
        } catch (_) {}
      }
      return false;
    }

    // Rebind sounds (FFI impl does work; Web no-op)
    if (rebindSounds) {
      for (final s in pausedSounds) {
        try {
          s._rebindAfterDeviceChange(this);
        } catch (_) {}
      }
      for (final s in pausedSounds) {
        try {
          s.play();
        } catch (_) {}
      }
    }

    // Recreate / re-init monitor player (simplest: dispose + new)
    if (monitorPlayer != null) {
      if (monitorPlayer.isInit) {
        try {
          monitorPlayer.dispose();
        } catch (_) {}
      }
      final newPlayer = StreamPlayer(mainEngine: this);
      await newPlayer.init(
        channels: monChannels ?? 1,
        sampleRate: monRate ?? 48000,
        bufferMs: monBufferMs ?? 240,
        format: AudioFormat.float32,
      );
      if (monitorVolume != null) {
        newPlayer.volume = monitorVolume;
      }
      if (monitorWasStarted) {
        newPlayer.start();
      }
      // Let caller replace their reference
      monitorPlayer._replaceFrom(newPlayer);
    }

    return true;
  }

  /// Gracefully shut down the engine.
  /// PlatformEngine does not expose `uninit`; we just dispose.
  Future<void> uninit() async {
    if (!isInit) return;
    try {
      _engine.dispose();
    } catch (_) {}
    isInit = false;
  }
}

/// A sound.
final class Sound {
  Sound._(PlatformSound sound) : _sound = sound;

  final PlatformSound _sound;

  /// a `double` greater than `0` (values greater than `1` may behave differently from platform to platform)
  double get volume => _sound.volume;
  set volume(double value) => _sound.volume = value < 0 ? 0 : value;

  Duration get duration =>
      Duration(milliseconds: (_sound.duration * 1000).toInt());

  bool get isLooped => _sound.looping.$1;
  Duration get loopDelay => Duration(milliseconds: _sound.looping.$2);

  /// Starts a sound. Stopped and played again if it is already started.
  void play() {
    if (_sound.looping.$1) _sound.looping = (false, 0);

    _sound.replay();
  }

  /// Starts sound looping.
  ///
  /// `delay` is clamped positive
  void playLooped({Duration delay = Duration.zero}) {
    final delayMs = delay < Duration.zero ? 0 : delay.inMilliseconds;
    if (!_sound.looping.$1 || _sound.looping.$2 != delayMs) {
      _sound.looping = (true, delayMs);
    }

    _sound.play();
  }

  /// Does not reset a sound position.
  ///
  /// If sound is looped, when played again will wait `loopDelay` and play. If you do not want this, use `stop()`.
  void pause() {
    if (_sound.looping.$1) _sound.looping = (false, 0);

    _sound.pause();
  }

  /// Resets a sound position.
  ///
  /// If sound is looped, when played again will NOT wait `loopDelay` and play. If you do not want this, use `pause()`.
  void stop() {
    if (_sound.looping.$1) _sound.looping = (false, 0);

    _sound.stop();
  }

  void unload() => _sound.unload();

  void _rebindAfterDeviceChange(Engine engine) {
    // Delegates to platform implementation (FFI will perform real rebind, Web no-op).
    _sound.rebindToEngine(engine._engine);
  }
}

final class Recorder {
  Recorder({Engine? mainEngine})
    : engine = mainEngine ?? Engine(),
      _recorder = MiniaudioDartPlatformInterface.instance.createRecorder();

  final PlatformRecorder _recorder;
  Engine engine;
  late int sampleRate;
  late int channels;
  late int format;
  late int bufferDurationSeconds;
  bool isInit = false;
  bool isRecording = false;

  /// Initializes the recorder's engine.
  Future<void> initEngine([int periodMs = 10]) async {
    await engine.init(periodMs);
  }

  /// Initializes the recorder to save to a file.
  Future<void> initFile(
    String filename, {
    int sampleRate = 48000,
    int channels = 1,
    int format = AudioFormat.float32,
  }) async {
    if (sampleRate <= 0 || channels <= 0) {
      throw ArgumentError("Invalid recorder parameters");
    }
    if (!isInit) {
      if (!engine.isInit) {
        await initEngine();
      }
      this.sampleRate = sampleRate;
      this.channels = channels;
      this.format = format;
      await _recorder.initFile(
        filename,
        sampleRate: sampleRate,
        channels: channels,
        format: format,
      );
      isInit = true;
    }
  }

  /// Initializes the recorder for streaming.
  Future<void> initStream({
    int sampleRate = 48000, // FIX
    int channels = 1,
    int format = AudioFormat.float32,
    int bufferDurationSeconds = 5,
  }) async {
    if (sampleRate <= 0 || channels <= 0 || bufferDurationSeconds <= 0) {
      throw ArgumentError("Invalid recorder parameters");
    }
    if (!isInit) {
      if (!engine.isInit) {
        await initEngine();
      }
      this.sampleRate = sampleRate;
      this.channels = channels;
      this.format = format;
      this.bufferDurationSeconds = bufferDurationSeconds;
      await _recorder.initStream(
        sampleRate: sampleRate,
        channels: channels,
        format: format,
        bufferDurationSeconds: bufferDurationSeconds,
      );
      isInit = true;
    }
  }

  /// Starts recording.
  void start() {
    _recorder.start();
    isRecording = true;
  }

  /// Stops recording.
  void stop() {
    _recorder.stop();
    isRecording = false;
  }

  /// Gets the recorded buffer.
  Float32List getBuffer(int framesToRead) => _recorder.getBuffer(framesToRead);

  /// Gets available frames from the recorder.
  int getAvailableFrames() => _recorder.getAvailableFrames();

  /// Pull a chunk (non-blocking). Returns empty list if none.
  Float32List readChunk({int maxFrames = 512}) =>
      _recorder.readChunk(maxFrames: maxFrames);

  /// Streams recorded audio using readChunk (preferred).
  Stream<Float32List> stream({int intervalMs = 20, int maxFramesPerChunk = 0}) {
    if (!isInit || !isRecording) {
      throw StateError("Recorder is not initialized or not recording");
    }
    final interval = Duration(milliseconds: intervalMs);
    return Stream.periodic(interval, (_) {
      final framesAvail = getAvailableFrames();
      if (framesAvail <= 0) return Float32List(0);
      final limit = maxFramesPerChunk > 0 ? maxFramesPerChunk : framesAvail;
      return readChunk(maxFrames: limit);
    }).where((c) => c.isNotEmpty);
  }

  /// Enable real-time monitoring to a StreamPlayer (creates/initializes it if needed).
  Future<void> enableMonitoring(
    StreamPlayer streamPlayer, {
    int? channels,
    int? sampleRate,
    int bufferMs = 120,
  }) async {
    final ch = channels ?? this.channels;
    final sr = sampleRate ?? this.sampleRate;
    if (!streamPlayer.engine.isInit) {
      await streamPlayer.engine.init();
      await streamPlayer.engine.start();
    }
    if (!streamPlayer._isInit) {
      await streamPlayer.init(channels: ch, sampleRate: sr, bufferMs: bufferMs);
      streamPlayer.start();
    }
  }

  /// Enable inline Opus encoding inside the native/Web audio callback.
  /// Returns false if Opus not available or already enabled but failed to configure.
  Future<bool> enableOpusEncoding({
    int targetBitrate = 64000,
    bool vbr = true,
    int complexity = 5,
    bool fec = false,
    int expectedPacketLossPercent = 0,
    bool dtx = false,
  }) => _recorder.enableOpusEncoding(
    targetBitrate: targetBitrate,
    vbr: vbr,
    complexity: complexity,
    fec: fec,
    expectedPacketLossPercent: expectedPacketLossPercent,
    dtx: dtx,
  );

  /// Number of encoded packets currently queued.
  int encodedPacketCount() => _recorder.encodedPacketCount();

  /// Dequeues a single framed encoded packet ([codec_id][flags][seq][len][payload]).
  /// Returns empty Uint8List if none.
  Uint8List dequeueEncodedPacket({int maxPacketBytes = 1500}) =>
      _recorder.dequeueEncodedPacket(maxPacketBytes: maxPacketBytes);

  /// Disposes of the recorder resources.
  void dispose() {
    _recorder.dispose();
  }

  /// Enumerate input devices. Returns (name, isDefault).
  Future<List<(String, bool)>> enumerateInputDevices() =>
      _recorder.enumerateCaptureDevices();

  /// Switch input device by index, preserving the stream state.
  Future<bool> switchInputDevicePreservingStream(int index) async {
    final wasRecording = isRecording;
    // Do NOT tear down ring buffer.
    final ok = await _recorder.selectCaptureDeviceByIndex(index);
    if (!ok) return false;
    if (wasRecording && !isRecording) {
      // Underlying implementation keeps isRecording; but defensive restart.
      try {
        _recorder.start();
      } catch (_) {}
    }
    return true;
  }

  /// Polls input device generation and emits updated device lists.
  /// Caller listens to the stream for hot device changes.
  Stream<List<(String, bool)>> inputDeviceChanges({
    Duration interval = const Duration(seconds: 1),
  }) async* {
    var lastGen = -1;
    while (true) {
      await Future.delayed(interval);
      if (!isInit) continue;
      final gen = _recorder.getCaptureDeviceGeneration();
      if (gen != lastGen) {
        lastGen = gen;
        try {
          yield await _recorder.enumerateCaptureDevices();
        } catch (_) {}
      }
    }
  }

  int pushInlineEncoderFloat32(Float32List frames) {
    // Use dynamic to avoid relying on interface additions (optional feature).
    final dynamic impl = _recorder;
    try {
      return impl.pushInlineEncoderFloat32(frames) as int;
    } catch (_) {
      throw MiniaudioDartPlatformException(
        "Inline encoder feed not supported on this platform",
      );
    }
  }

  bool flushInlineEncoder({bool padWithZeros = true}) {
    final dynamic impl = _recorder;
    try {
      return impl.flushInlineEncoder(padWithZeros: padWithZeros) as bool;
    } catch (_) {
      return false;
    }
  }
}

/// A generator for waveforms and noise.
final class Generator {
  Generator({Engine? mainEngine})
    : engine = mainEngine ?? Engine(),
      _generator = MiniaudioDartPlatformInterface.instance.createGenerator();

  double get volume => _generator.volume;
  set volume(double value) => _generator.volume = value < 0 ? 0 : value;

  final PlatformGenerator _generator;
  late Engine engine;
  bool isInit = false;
  bool isGenerating = false;
  int _channels = 1;
  int _sampleRate = 48000;

  /// Initializes the generator's engine.
  Future initEngine([int periodMs = 10]) async {
    await engine.init(periodMs);
  }

  /// Initializes the generator.
  Future<void> init(
    int format,
    int channels,
    int sampleRate,
    int bufferDurationSeconds,
  ) async {
    if (!engine.isInit) {
      await initEngine();
    }
    if (!isInit) {
      await _generator.init(
        format,
        channels,
        sampleRate,
        bufferDurationSeconds,
      );
      _channels = channels;
      _sampleRate = sampleRate;
      isInit = true;
    }
  }

  /// Sets the waveform type, frequency, and amplitude.
  void setWaveform(WaveformType type, double frequency, double amplitude) =>
      _generator.setWaveform(type, frequency, amplitude);

  /// Sets the pulse wave frequency, amplitude, and duty cycle.
  void setPulsewave(double frequency, double amplitude, double dutyCycle) =>
      _generator.setPulsewave(frequency, amplitude, dutyCycle);

  /// Sets the noise type, seed, and amplitude.
  void setNoise(NoiseType type, int seed, double amplitude) =>
      _generator.setNoise(type, seed, amplitude);

  /// Starts the generator.
  void start() {
    _generator.start();
    isGenerating = true;
  }

  /// Stops the generator.
  void stop() {
    _generator.stop();
    isGenerating = false;
  }

  /// Reads generated data.
  Float32List getBuffer(int framesToRead) => _generator.getBuffer(framesToRead);

  /// Gets the number of available frames in the generator's buffer.
  int getAvailableFrames() => _generator.getAvailableFrames();

  Stream<Float32List> stream({int chunkSizeMs = 20}) {
    if (!isInit || !isGenerating) {
      throw StateError("Recorder is not initialized or not recording");
    }

    final chunkSizeSamples = (_sampleRate * chunkSizeMs) ~/ 1000;

    return Stream.periodic(Duration(milliseconds: chunkSizeMs), (_) {
      final availableFrames = getAvailableFrames();
      if (availableFrames >= chunkSizeSamples) {
        return getBuffer(chunkSizeSamples);
      } else {
        return Float32List(0);
      }
    }).where((chunk) => chunk.isNotEmpty);
  }

  /// Disposes of the generator resources.
  void dispose() {
    _generator.dispose();
  }
}

/// Streamed playback of raw PCM (low latency, no per-chunk sounds).
final class StreamPlayer {
  StreamPlayer({Engine? mainEngine}) : engine = mainEngine ?? Engine();

  final Engine engine;
  PlatformStreamPlayer? _player;
  bool _isInit = false;
  int _channels = 1;
  int _sampleRate = 48000;
  int _format = AudioFormat.float32;
  int _bufferMs = 100;
  bool _isStarted = false;

  // Initialize the underlying stream player.
  Future<void> init({
    int format = AudioFormat.float32,
    int channels = 1,
    int sampleRate = 48000,
    int bufferMs = 100,
  }) async {
    if (_isInit) return;
    if (!engine.isInit) {
      await engine.init();
      await engine.start();
    }
    if (format != AudioFormat.float32) {
      throw Exception("Only AudioFormat.float32 is supported by StreamPlayer");
    }
    _channels = channels;
    _sampleRate = sampleRate;
    _format = format;
    _bufferMs = bufferMs;
    _player = MiniaudioDartPlatformInterface.instance.createStreamPlayer(
      engine: engine._engine,
      format: _format,
      channels: _channels,
      sampleRate: _sampleRate,
      bufferMs: _bufferMs,
    );
    _isInit = true;
  }

  double get volume => _player?.volume ?? 1.0;
  set volume(double v) {
    if (_player == null) return;
    _player!.volume = v < 0 ? 0 : v;
  }

  void start() {
    _ensureInit();
    _player!.start();
    _isStarted = true;
  }

  void stop() {
    if (_player == null) return;
    _player!.stop();
    _isStarted = false;
  }

  void clear() {
    if (_player == null) return;
    _player!.clear();
  }

  bool get isStarted => _isStarted;
  bool get isInit => _isInit;
  int get channels => _channels;
  int get sampleRate => _sampleRate;
  int get bufferMs => _bufferMs;

  int writeFloat32(Float32List interleaved) {
    _ensureInit();
    if (interleaved.isEmpty) return 0;
    return _player!.writeFloat32(interleaved);
  }

  /// Push a framed encoded packet (Opus/PCM) for immediate decode + playback.
  /// Packet framing must match recorder inline encoder format.
  bool pushEncodedPacket(Uint8List packet) {
    _ensureInit();
    if (packet.isEmpty) return false;
    return _player!.pushEncodedPacket(packet);
  }

  void dispose() {
    _player?.dispose();
    _player = null;
    _isInit = false;
  }

  void _ensureInit() {
    if (!_isInit || _player == null) {
      throw StateError("StreamPlayer not initialized. Call init() first.");
    }
  }

  void _replaceFrom(StreamPlayer other) {
    // Copy essential internal state from the freshly created instance.
    _player = other._player;
    _isInit = other._isInit;
    _channels = other._channels;
    _sampleRate = other._sampleRate;
    _bufferMs = other._bufferMs;
    _format = other._format;
    _isStarted = other._isStarted;
    volume = other.volume;
    // Dispose the donor's shell (avoid double free; donor should not be used).
    other._player = null;
  }
}

class EngineAlreadyInitError extends Error {
  EngineAlreadyInitError([this.message]);

  final String? message;

  @override
  String toString() =>
      message == null ? "Engine already init" : "Engine already init: $message";
}
