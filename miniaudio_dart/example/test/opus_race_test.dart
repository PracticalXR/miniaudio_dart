import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:miniaudio_dart/miniaudio_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OpusInlineRace', () {
    late Engine engine;
    Recorder? rec;
    StreamPlayer? player;

    setUpAll(() async {
      engine = Engine();
      await engine.init();
      rec = Recorder();
      await rec!.initStream(
          sampleRate: 48000, channels: 1, format: AudioFormat.float32);
      player = StreamPlayer(mainEngine: engine);
      await player!.init(sampleRate: 48000, channels: 1, bufferMs: 300);
      await engine.start();
      player!.start();
      final ok = await rec!.enableOpusEncoding();
      expect(ok, isTrue);
    });

    tearDownAll(() async {
      player?.dispose();
      rec?.dispose();
      await engine.uninit();
    });

    test('external feed vs playback stress', () async {
      final r = rec!;
      // Start capture to enable auto path; immediately disable and do manual feed to test transition.
      r.start();
      int packets = 0;
      bool stop = false;

      // Packet drain (decode)
      final drain = Timer.periodic(const Duration(milliseconds: 15), (_) {
        final pending = r.encodedPacketCount();
        for (int i = 0; i < pending; i++) {
          final pkt = r.dequeueEncodedPacket();
          if (pkt.isNotEmpty) {
            packets++;
            player!.pushEncodedPacket(pkt);
          }
        }
      });

      // Two concurrent feeders with varied chunk sizes (multiples + non-multiples)
      double phase = 0.0;
      final feeders = <Timer>[];
      for (int t = 0; t < 2; t++) {
        feeders.add(Timer.periodic(Duration(milliseconds: 5 + t), (_) {
          if (stop) return;
          final mult = (math.Random().nextInt(3) + 1); // 1..3
          final frames = 960 * mult;
          final buf = Float32List(frames);
          for (int i = 0; i < frames; i++) {
            buf[i] = math.sin(phase) * 0.2;
            phase += 2 * math.pi * 440 / 48000;
            if (phase > 2 * math.pi) phase -= 2 * math.pi;
          }
          r.pushInlineEncoderFloat32(buf);
        }));
      }

      await Future.delayed(const Duration(seconds: 4));
      stop = true;
      for (final f in feeders) {
        f.cancel();
      }
      drain.cancel();
      r.flushInlineEncoder(padWithZeros: true);
      expect(packets, greaterThan(10));
    });

    test('rapid start/stop with encoder attached', () async {
      final r = rec!;
      for (int i = 0; i < 30; i++) {
        r.start();
        await Future.delayed(const Duration(milliseconds: 40));
        r.stop();
      }
    });
  });
}
