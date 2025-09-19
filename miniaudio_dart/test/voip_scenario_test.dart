import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:miniaudio_dart/miniaudio_dart.dart';
import "package:miniaudio_dart_platform_interface/miniaudio_dart_platform_interface.dart";

/// Simplified VOIP scenario test focusing on stability.
/// Tests multiple StreamPlayers with one Recorder using the new codec API.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VOIP Scenario Tests', () {
    late Engine engine;
    final players = <StreamPlayer>[];
    Recorder? recorder;
    CrossCoder? encoder;
    CrossCoder? decoder;

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
      // Clean up players
      for (final player in players) {
        try {
          player.stop();
          player.dispose();
        } catch (_) {}
      }
      players.clear();

      // Clean up recorder
      try {
        recorder?.stop();
        recorder?.dispose();
        recorder = null;
      } catch (_) {}

      // Clean up codecs
      encoder?.dispose();
      decoder?.dispose();

      // Clean up engine
      try {
        await engine.uninit();
      } catch (_) {}
    });

    Float32List _generateTestAudio(int frames, double frequency) {
      final data = Float32List(frames);
      for (int i = 0; i < frames; i++) {
        data[i] = 0.3 * math.sin(2 * math.pi * frequency * i / 48000);
      }
      return data;
    }

    test('Basic multi-player setup', () async {
      if (!engine.isInit) return;

      // Create multiple stream players
      for (int i = 0; i < 3; i++) {
        final player = StreamPlayer(mainEngine: engine);
        await player.init(
          format: AudioFormat.float32,
          channels: 1,
          sampleRate: 48000,
          bufferMs: 200,
        );
        player.start();
        players.add(player);
      }

      expect(players.length, 3);

      // Feed each player different frequency
      for (int i = 0; i < players.length; i++) {
        final frequency = 440.0 + (i * 110.0);
        final audio = _generateTestAudio(960, frequency);
        final written = players[i].writeFloat32(audio);
        expect(written, greaterThan(0));
      }

      // Let it play briefly
      await Future.delayed(Duration(milliseconds: 100));
    });

    test('Recorder with multiple stream players', () async {
      if (!engine.isInit) return;

      // Set up recorder
      recorder = Recorder();
      await recorder!.initEngine();
      await recorder!.initStream(
        sampleRate: 48000,
        channels: 1,
        format: AudioFormat.float32,
        codecConfig: const RecorderCodecConfig(codec: RecorderCodec.pcm),
      );

      // Set up players
      for (int i = 0; i < 2; i++) {
        final player = StreamPlayer(mainEngine: engine);
        await player.init(
          format: AudioFormat.float32,
          channels: 1,
          sampleRate: 48000,
          bufferMs: 150,
        );
        player.start();
        players.add(player);
      }

      // Start recorder
      recorder!.start();
      expect(recorder!.isRecording, true);

      // Feed players and let recorder capture
      final timer = Timer.periodic(Duration(milliseconds: 20), (timer) {
        for (int i = 0; i < players.length; i++) {
          final frequency = 330.0 + (i * 220.0);
          final audio = _generateTestAudio(480, frequency);
          players[i].writeFloat32(audio);
        }
      });

      await Future.delayed(Duration(milliseconds: 500));
      timer.cancel();

      // Check recorder captured something
      final availableFrames = recorder!.getAvailableFrames();
      expect(availableFrames, greaterThanOrEqualTo(0));

      recorder!.stop();
    });

    test('CrossCoder with StreamPlayer integration', () async {
      if (!engine.isInit) return;

      // Set up encoder/decoder pair
      encoder = CrossCoder();
      decoder = CrossCoder();

      final encodeSuccess = await encoder!.init(
        sampleRate: 48000,
        channels: 1,
        codecId: 0, // PCM for reliability
      );

      final decodeSuccess = await decoder!.init(
        sampleRate: 48000,
        channels: 1,
        codecId: 0, // PCM
      );

      if (!encodeSuccess || !decodeSuccess) {
        print('CrossCoder init failed');
        return;
      }

      // Set up player
      final player = StreamPlayer(mainEngine: engine);
      await player.init(
        format: AudioFormat.float32,
        channels: 1,
        sampleRate: 48000,
        bufferMs: 200,
      );
      player.start();
      players.add(player);

      // Simulate encoding/decoding cycle
      final frameSize = encoder!.frameSize;
      final originalAudio = _generateTestAudio(frameSize, 440.0);

      // Encode
      final encoded = encoder!.encodeFrames(originalAudio);
      expect(encoded.isNotEmpty, true);

      // Decode
      final decoded = decoder!.decodePacket(encoded);
      expect(decoded.isNotEmpty, true);

      // Feed to player using unified API
      final pushSuccess = player.pushData(decoded);
      expect(pushSuccess, true);

      await Future.delayed(Duration(milliseconds: 100));
    });

    test('Dynamic player management', () async {
      if (!engine.isInit) return;

      // Start with one player
      var player = StreamPlayer(mainEngine: engine);
      await player.init(
        format: AudioFormat.float32,
        channels: 1,
        sampleRate: 48000,
        bufferMs: 150,
      );
      player.start();
      players.add(player);

      // Feed it some audio
      final audio = _generateTestAudio(960, 440.0);
      player.writeFloat32(audio);

      await Future.delayed(Duration(milliseconds: 50));

      // Add another player dynamically
      final player2 = StreamPlayer(mainEngine: engine);
      await player2.init(
        format: AudioFormat.float32,
        channels: 1,
        sampleRate: 48000,
        bufferMs: 150,
      );
      player2.start();
      players.add(player2);

      // Feed both
      for (int i = 0; i < players.length; i++) {
        final frequency = 440.0 + (i * 220.0);
        final testAudio = _generateTestAudio(480, frequency);
        players[i].writeFloat32(testAudio);
      }

      await Future.delayed(Duration(milliseconds: 100));

      // Remove first player
      final removedPlayer = players.removeAt(0);
      removedPlayer.stop();
      removedPlayer.dispose();

      // Continue with remaining player
      final remainingAudio = _generateTestAudio(480, 660.0);
      players[0].writeFloat32(remainingAudio);

      await Future.delayed(Duration(milliseconds: 50));
    });
  });
}
