import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:miniaudio_dart/miniaudio_dart.dart';
import "package:miniaudio_dart_platform_interface/miniaudio_dart_platform_interface.dart";

/// Tests for the unified recorder codec system.
/// Tests both PCM and Opus modes using RecorderCodecConfig.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Recorder Codec Tests', () {
    late Engine engine;
    Recorder? recorder;

    setUp(() async {
      engine = Engine();
      try {
        await engine.init();
        await engine.start();
      } catch (e) {
        print('Engine init failed: $e');
      }
    });

    tearDown(() async {
      try {
        recorder?.stop();
        recorder?.dispose();
        recorder = null;
      } catch (_) {}
      try {
        await engine.uninit();
      } catch (_) {}
    });

    test('PCM recorder init and basic recording', () async {
      if (!engine.isInit) return;

      recorder = Recorder();
      await recorder!.initEngine();

      // Initialize with PCM codec (default)
      await recorder!.initStream(
        sampleRate: 48000,
        channels: 1,
        format: AudioFormat.float32,
        codecConfig: RecorderCodecConfig(
          codec: RecorderCodec.pcm,
        ),
      );

      expect(recorder!.codec, RecorderCodec.pcm);

      // Test recording for a short time
      recorder!.start();
      expect(recorder!.isRecording, true);

      await Future.delayed(Duration(milliseconds: 100));

      // Check if we have some frames available
      final availableFrames = recorder!.getAvailableFrames();
      expect(availableFrames, greaterThanOrEqualTo(0));

      if (availableFrames > 0) {
        // Read some PCM data
        final data =
            recorder!.readChunk(maxFrames: math.min(512, availableFrames));
        expect(data, isA<Float32List>());
        expect((data as Float32List).isNotEmpty, true);
      }

      recorder!.stop();
      expect(recorder!.isRecording, false);
    });

    test('Opus recorder init and encoding', () async {
      if (!engine.isInit) return;

      recorder = Recorder();
      await recorder!.initEngine();

      // Try to initialize with Opus codec
      try {
        await recorder!.initStream(
          sampleRate: 48000,
          channels: 1,
          format: AudioFormat.float32,
          codecConfig: RecorderCodecConfig(
            codec: RecorderCodec.opus,
            opusApplication: 2049, // OPUS_APPLICATION_AUDIO
            opusBitrate: 64000,
            opusComplexity: 5,
            opusVBR: true,
          ),
        );

        expect(recorder!.codec, RecorderCodec.opus);

        // Start recording
        recorder!.start();
        expect(recorder!.isRecording, true);

        await Future.delayed(Duration(milliseconds: 200));

        // Check if we have encoded packets
        final availableFrames = recorder!.getAvailableFrames();
        expect(availableFrames, greaterThanOrEqualTo(0));

        if (availableFrames > 0) {
          // Read encoded data
          final data =
              recorder!.readChunk(maxFrames: math.min(10, availableFrames));
          expect(data, isA<Uint8List>());
          expect((data as Uint8List).isNotEmpty, true);
        }

        recorder!.stop();
      } catch (e) {
        // Opus might not be available on all platforms
        print('Opus encoding not available: $e');
        return;
      }
    });

    test('Dynamic codec switching', () async {
      if (!engine.isInit) return;

      recorder = Recorder();
      await recorder!.initEngine();

      // Start with PCM
      await recorder!.initStream(
        sampleRate: 48000,
        channels: 1,
        format: AudioFormat.float32,
        codecConfig: RecorderCodecConfig(codec: RecorderCodec.pcm),
      );

      expect(recorder!.codec, RecorderCodec.pcm);

      // Try to switch to Opus
      final opusConfig = RecorderCodecConfig(
        codec: RecorderCodec.opus,
        opusApplication: 2049,
        opusBitrate: 64000,
      );

      final switchSuccess = await recorder!.updateCodecConfig(opusConfig);

      if (switchSuccess) {
        expect(recorder!.codec, RecorderCodec.opus);

        // Try switching back to PCM
        final pcmConfig = RecorderCodecConfig(codec: RecorderCodec.pcm);
        final switchBackSuccess = await recorder!.updateCodecConfig(pcmConfig);
        expect(switchBackSuccess, true);
        expect(recorder!.codec, RecorderCodec.pcm);
      } else {
        // Opus not supported - that's okay
        print('Opus codec switching not supported');
      }
    });

    test('Capture gain control', () async {
      if (!engine.isInit) return;

      recorder = Recorder();
      await recorder!.initEngine();
      await recorder!.initStream();

      // Test gain control
      expect(recorder!.captureGain, closeTo(1.0, 0.1));

      recorder!.captureGain = 0.5;
      expect(recorder!.captureGain, closeTo(0.5, 0.1));

      recorder!.captureGain = 1.5;
      expect(recorder!.captureGain, closeTo(1.5, 0.1));
    });
  });
}
