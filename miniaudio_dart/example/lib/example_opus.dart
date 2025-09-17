// Simple Opus encode/decode loopback verification.
// Requires build with HAVE_OPUS.

import "dart:async";
import "dart:typed_data";
import "dart:math" as math;
import "package:flutter/material.dart";
import "package:miniaudio_dart/miniaudio_dart.dart";
import "package:miniaudio_dart/miniaudio_flutter.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
      title: "Opus Loopback Example", home: OpusExamplePage()));
}

class OpusExamplePage extends StatefulWidget {
  const OpusExamplePage({super.key});
  @override
  State<OpusExamplePage> createState() => _OpusExamplePageState();
}

class _OpusExamplePageState extends State<OpusExamplePage> {
  final engine = Engine();
  Recorder? recorder;
  StreamPlayer? decodedPlayer;
  Timer? pumpTimer;

  bool _running = false;
  int _packetsDecoded = 0;
  int _packetsSent = 0;
  int _framesDecoded = 0;
  late Future<void> _initFuture;

  bool _externalFeed = false;
  Timer? _externalFeedTimer;
  double _extPhase = 0.0;
  static const int _extSampleRate = 48000;
  static const int _extChannels = 1;

  @override
  void initState() {
    super.initState();
    _initFuture = _init();
  }

  Future<void> _init() async {
    await engine.init();
    final r = Recorder();
    await r.initStream(
        sampleRate: 48000, channels: 1, format: AudioFormat.float32);
    final sp = StreamPlayer(mainEngine: engine);
    await sp.init(sampleRate: 48000, channels: 1, bufferMs: 200);
    await engine.start();
    sp.start();
    setState(() {
      recorder = r;
      decodedPlayer = sp;
    });
  }

  void _start() async {
    if (_running || recorder == null) return;

    // Attach encoder
    final ok = await recorder!.enableOpusEncoding();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Opus unavailable")));
      }
      return;
    }

    if (!_externalFeed) {
      // Use microphone capture path
      recorder!.start();
    } else {
      _startExternalFeed(); // manual PCM injection
    }

    _running = true;

    pumpTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final rec = recorder;
      final sp = decodedPlayer;
      if (rec == null || sp == null) return;
      final pending = rec.encodedPacketCount();
      for (int i = 0; i < pending; i++) {
        final pkt = rec.dequeueEncodedPacket();
        if (pkt.isEmpty) break;
        _packetsSent++;
        if (sp.pushEncodedPacket(pkt)) {
          _packetsDecoded++;
        }
      }
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  void _startExternalFeed() {
    // Generate 20 ms Opus-sized frames (960 frames @ 48k) of a sine tone.
    const int frameSize = 960; // matches encoder frame
    final double freq = 440.0;
    final double twoPi = math.pi * 2;
    final double phaseInc = twoPi * freq / _extSampleRate;

    _externalFeedTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      // Build interleaved float32 frames
      final data = Float32List(frameSize * _extChannels);
      for (int i = 0; i < frameSize; i++) {
        final s = math.sin(_extPhase);
        _extPhase += phaseInc;
        if (_extPhase > twoPi) _extPhase -= twoPi;
        data[i] = (s * 0.4).toDouble();
      }
      // Push into inline encoder (bypasses mic capture)
      recorder?.pushInlineEncoderFloat32(data);
    });
  }

  void _stop() {
    if (!_running) return;
    pumpTimer?.cancel();
    _externalFeedTimer?.cancel();
    if (!_externalFeed) {
      recorder?.stop();
    } else {
      // Flush remaining partial frame (pad) when using external feed.
      recorder?.flushInlineEncoder(padWithZeros: true);
    }
    _running = false;
    setState(() {});
  }

  @override
  void dispose() {
    pumpTimer?.cancel();
    _externalFeedTimer?.cancel();
    recorder?.dispose();
    decodedPlayer?.dispose();
    engine.uninit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _initFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) {
            return Scaffold(
              body: Center(child: Text("Init error: ${snap.error}")),
            );
          }
          final ready = recorder != null && decodedPlayer != null;
          return Scaffold(
            appBar: AppBar(title: const Text("Opus Encode/Decode Loopback")),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Status: ${_running ? "Running" : "Stopped"}"),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: (!ready || _running) ? null : _start,
                        child: const Text("Start Loopback"),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: (_running) ? _stop : null,
                        child: const Text("Stop"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text("Packets sent:   $_packetsSent"),
                  Text("Packets decoded: $_packetsDecoded"),
                  Text("Frames decoded (est): $_framesDecoded"),
                  const SizedBox(height: 16),
                  const Text(
                    "Flow:\n"
                    "- Capture mic frames\n"
                    "- Inline Opus encode (20 ms)\n"
                    "- Dequeue packets\n"
                    "- Push to StreamPlayer (decode+play)\n"
                    "Integrate networking by sending framed packets remotely.",
                  ),
                  Row(
                    children: [
                      Switch(
                        value: _externalFeed,
                        onChanged: _running
                            ? null
                            : (v) => setState(() {
                                  _externalFeed = v;
                                }),
                      ),
                      const SizedBox(width: 8),
                      const Text("External PCM feed (sine 440Hz)"),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
}
