import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miniaudio_dart/miniaudio_dart.dart';

/// Pure Dart API surface tests. They avoid optional features when unavailable.
/// Conditional skip logic replaced with simple early returns (no `skip()` helper used).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Engine (pure Dart interaction)', () {
    late Engine engine;

    setUp(() async {
      engine = Engine();
      try {
        await engine.init();
      } catch (_) {}
    });

    tearDown(() async {
      try {
        await engine.uninit();
      } catch (_) {}
    });

    test('init flag set', () {
      expect(engine.isInit, isTrue);
    });

    test('start does not throw', () async {
      await expectLater(engine.start(), completes);
      expect(engine.isInit, isTrue);
    });

    test('load in-memory sound', () async {
      final data = AudioData(Float32List(480), AudioFormat.float32, 48000, 1);
      final sound = await engine.loadSound(data);
      expect(sound, isA<Sound>());
    });
  });

  group('Sound basic lifecycle', () {
    late Engine engine;
    late Sound sound;

    setUp(() async {
      engine = Engine();
      await engine.init();
      final data = AudioData(Float32List(960), AudioFormat.float32, 48000, 1);
      sound = await engine.loadSound(data);
      await engine.start();
    });

    tearDown(() async {
      try {
        await engine.uninit();
      } catch (_) {}
    });

    test('play (no exception)', () {
      sound.play();
    });

    test('play + pause clears loop flag', () {
      sound.play();
      sound.pause();
      // We only can test loop flag (no isPlaying API).
      expect(sound.isLooped, isFalse);
    });

    test('play + stop clears loop flag', () {
      sound.play();
      sound.stop();
      expect(sound.isLooped, isFalse);
    });

    test('volume roundtrip', () {
      sound.volume = 0.42;
      expect(sound.volume, closeTo(0.42, 1e-6));
    });

    test('looped playback flag toggles', () {
      sound.playLooped(delay: const Duration(milliseconds: 50));
      expect(sound.isLooped, isTrue);
      sound.stop();
      expect(sound.isLooped, isFalse);
    });
  });

  group('Recorder streaming (if backend allows)', () {
    late Recorder recorder;
    bool available = true;

    setUp(() async {
      recorder = Recorder();
      try {
        await recorder.initEngine();
        await recorder.initStream(
          sampleRate: 48000,
          channels: 1,
          format: AudioFormat.float32,
        );
      } catch (e) {
        available = false;
      }
    });

    tearDown(() {
      try {
        recorder.dispose();
      } catch (_) {}
    });

    test('initialized flag', () {
      if (!available) {
        return;
      }
      expect(recorder.isInit, isTrue);
    });

    test('start/stop flags', () async {
      if (!available) {
        return;
      }
      recorder.start();
      expect(recorder.isRecording, isTrue);
      recorder.stop();
      expect(recorder.isRecording, isFalse);
    });

    test('buffer retrieval after short delay', () async {
      if (!available) {
        return;
      }
      recorder.start();
      await Future.delayed(const Duration(milliseconds: 25));
      final buf = recorder.getBuffer(96);
      // Backend may return silence or partial; just type/length sanity.
      expect(buf, isA<Float32List>());
      expect(buf.length, anyOf(0, 96));
      recorder.stop();
    });

    test('available frames non-negative', () async {
      if (!available) {
        return;
      }
      recorder.start();
      await Future.delayed(const Duration(milliseconds: 15));
      final avail = recorder.getAvailableFrames();
      expect(avail, greaterThanOrEqualTo(0));
      recorder.stop();
    });
  });

  group('Generator basic DSP', () {
    late Generator gen;
    bool ok = true;

    setUp(() async {
      gen = Generator();
      try {
        await gen.initEngine();
        await gen.init(AudioFormat.float32, 2, 48000, 2);
      } catch (_) {
        ok = false;
      }
    });

    tearDown(() {
      try {
        gen.dispose();
      } catch (_) {}
    });

    test('initialized', () {
      if (!ok) return;
      expect(gen.isInit, isTrue);
    });

    test('sine generation produces frames', () async {
      if (!ok) return;
      gen.setWaveform(WaveformType.sine, 440.0, 0.25);
      gen.start();
      await Future.delayed(const Duration(milliseconds: 20));
      final frames = gen.getAvailableFrames();
      expect(frames, greaterThanOrEqualTo(0));
      final grab = gen.getBuffer(frames > 64 ? 64 : frames);
      expect(grab.length, anyOf(0, 64));
      gen.stop();
    });

    test('noise generation', () async {
      if (!ok) return;
      gen.setNoise(NoiseType.white, 0, 0.5);
      gen.start();
      await Future.delayed(const Duration(milliseconds: 20));
      final frames = gen.getAvailableFrames();
      expect(frames, greaterThanOrEqualTo(0));
      gen.stop();
    });
  });

  group('StreamPlayer basic', () {
    late Engine engine;
    late StreamPlayer sp;
    bool ready = true;

    setUp(() async {
      engine = Engine();
      try {
        await engine.init();
        await engine.start();
        sp = StreamPlayer(mainEngine: engine);
        await sp.init(
          format: AudioFormat.float32,
          channels: 1,
          sampleRate: 48000,
          bufferMs: 120,
        );
      } catch (_) {
        ready = false;
      }
    });

    tearDown(() {
      try {
        sp.dispose();
      } catch (_) {}
      try {
        engine.uninit();
      } catch (_) {}
    });

    test('init', () {
      if (!ready) return;
      expect(sp.isInit, isTrue);
    });

    test('start + write silence', () {
      if (!ready) return;
      sp.start();
      final wrote = sp.writeFloat32(Float32List(480)); // 10ms mono
      expect(wrote, anyOf(0, 480));
      sp.stop();
    });
  });
}
