// Simple Opus encode/decode loopback verification using new unified codec API.
// Shows both integrated Recorder codec and standalone CrossCoder approaches.

import "dart:async";
import "dart:typed_data";
import "dart:math" as math;
import "package:flutter/material.dart";
import "package:miniaudio_dart/miniaudio_dart.dart";
import "package:miniaudio_dart/miniaudio_flutter.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(title: "Opus Loopback Example", home: OpusExamplePage()),
  );
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
  CrossCoder? externalEncoder;
  Timer? pumpTimer;

  bool _running = false;
  int _packetsDecoded = 0;
  int _packetsSent = 0;
  int _bytesEncoded = 0;
  late Future<void> _initFuture;

  bool _useStandaloneCoder = false;
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
    try {
      await engine.init();

      // Create recorder (EXPLICIT PCM)
      final r = Recorder(mainEngine: engine);
      await r.initEngine();

      await r.initStream(
        sampleRate: 48000,
        channels: 1,
        format: AudioFormat.float32,
        bufferDurationSeconds: 5,
      );

      // Create StreamPlayer (slightly larger buffer to avoid glitches)
      final sp = StreamPlayer(mainEngine: engine);
      await sp.init(sampleRate: 48000, channels: 1, bufferMs: 120);
      await engine.start();
      sp.start();

      // Standalone CrossCoder (Opus)
      CrossCoder? crossCoder;
      try {
        crossCoder = CrossCoder();
        final encoderReady = await crossCoder.init(
          sampleRate: 48000,
          channels: 1,
          codecId: 1, // 1 = Opus
          application: 2049, // OPUS_APPLICATION_AUDIO
        );
        if (!encoderReady) {
          crossCoder.dispose();
          crossCoder = null;
        }
      } catch (e) {
        print('CrossCoder init failed: $e');
        crossCoder?.dispose();
        crossCoder = null;
      }

      setState(() {
        recorder = r;
        decodedPlayer = sp;
        externalEncoder = crossCoder;
      });
    } catch (e) {
      print('Init failed: $e');
      rethrow;
    }
  }

  void _start() async {
    if (_running || recorder == null || decodedPlayer == null) return;

    if (!_useStandaloneCoder) {
      // Method 1: Use recorder (PCM passthrough)
      recorder!.start();
    } else {
      // Method 2: Use standalone CrossCoder
      if (externalEncoder == null) {
        _showMessage("Standalone encoder not available");
        return;
      }
      _startExternalFeed();
    }

    _running = true;

    // Pump timer to transfer data from recorder to player
    pumpTimer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      _pumpData();
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  void _pumpData() {
    final rec = recorder;
    final sp = decodedPlayer;
    if (rec == null || sp == null) return;

    if (!_useStandaloneCoder) {
      // PCM passthrough (recorder guaranteed PCM)
      final availableFrames = rec.getAvailableFrames();
      if (availableFrames > 0) {
        try {
          final data = rec.getBuffer(availableFrames);
          if (data is Float32List && data.isNotEmpty) {
            _packetsSent++;
            final written = sp.writeFloat32(data);
            if (written > 0) _packetsDecoded++;
          }
        } catch (e) {
          print('Pump error: $e');
        }
      }
    }
    // External feed pumping is handled in timer callback
  }

  void _startExternalFeed() {
    if (externalEncoder == null) return;

    final frameSize = externalEncoder!.frameSize;
    final double freq = 440.0;
    final double twoPi = math.pi * 2;
    final double phaseInc = twoPi * freq / _extSampleRate;

    print('Starting external feed with frameSize: $frameSize');

    final frameDurationMs = (frameSize * 1000.0) / _extSampleRate;
    final timerMs = math.max(1, frameDurationMs.round());

    print('Frame duration: ${frameDurationMs}ms, Timer: ${timerMs}ms');

    _externalFeedTimer = Timer.periodic(Duration(milliseconds: timerMs), (_) {
      final encoder = externalEncoder;
      final player = decodedPlayer;
      if (encoder == null || player == null) return;

      try {
        // Generate exactly frameSize samples (mono)
        final data = Float32List(frameSize);
        for (int i = 0; i < frameSize; i++) {
          final s = math.sin(_extPhase);
          _extPhase += phaseInc;
          if (_extPhase > twoPi) _extPhase -= twoPi;
          data[i] = (s * 0.4);
        }

        // Correctly destructure the tuple
        final (packet, bytesWritten) = encoder.encodeFramesWithSize(data);
        if (packet.isNotEmpty && bytesWritten > 0) {
          _packetsSent++;
          _bytesEncoded += bytesWritten; // Track bytes too

          // Let StreamPlayer decode the Opus packet
          final ok = player.pushEncodedPacket(packet);
          if (ok) _packetsDecoded++;
        }
      } catch (e) {
        print('External feed error: $e');
      }
    });
  }

  void _stop() {
    if (!_running) return;
    pumpTimer?.cancel();
    _externalFeedTimer?.cancel();

    if (!_useStandaloneCoder) {
      recorder?.stop();
    }

    _running = false;
    setState(() {});
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _testCodecSwitching() async {
    _showMessage('Codec switching not yet implemented');
    // TODO: Implement when updateCodecConfig is available
  }

  @override
  void dispose() {
    pumpTimer?.cancel();
    _externalFeedTimer?.cancel();
    recorder?.dispose();
    decodedPlayer?.dispose();
    externalEncoder?.dispose();
    engine.uninit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _initFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) {
            return Scaffold(
                body: Center(child: Text("Init error: ${snap.error}")));
          }

          final ready = recorder != null && decodedPlayer != null;
          final hasStandaloneEncoder = externalEncoder != null;

          return Scaffold(
            appBar: AppBar(title: const Text("Codec Loopback Example")),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Status: ${_running ? "Running" : "Stopped"}"),
                  Text("Recorder: ${ready ? "Ready" : "Not Ready"}"),
                  Text(
                    "CrossCoder: ${hasStandaloneEncoder ? "Available" : "Not Available"}",
                  ),
                  const SizedBox(height: 8),

                  // Control buttons
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: (!ready || _running) ? null : _start,
                        child: Text(
                          _useStandaloneCoder
                              ? "Start CrossCoder"
                              : "Start Recorder",
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _running ? _stop : null,
                        child: const Text("Stop"),
                      ),
                      ElevatedButton(
                        onPressed:
                            (!ready || _running) ? null : _testCodecSwitching,
                        child: const Text("Test Feature"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Statistics
                  Text("Packets sent: $_packetsSent"),
                  Text("Packets decoded: $_packetsDecoded"),
                  Text("Bytes encoded: $_bytesEncoded"),

                  const SizedBox(height: 16),

                  // Mode selection
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Mode:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          RadioListTile<bool>(
                            title: const Text("Recorder Passthrough"),
                            subtitle:
                                const Text("Mic → Recorder → StreamPlayer"),
                            value: false,
                            groupValue: _useStandaloneCoder,
                            onChanged: _running
                                ? null
                                : (v) =>
                                    setState(() => _useStandaloneCoder = v!),
                          ),
                          RadioListTile<bool>(
                            title: const Text("CrossCoder Test"),
                            subtitle: const Text(
                              "Generated → CrossCoder → StreamPlayer",
                            ),
                            value: true,
                            groupValue: _useStandaloneCoder,
                            onChanged: (_running || !hasStandaloneEncoder)
                                ? null
                                : (v) =>
                                    setState(() => _useStandaloneCoder = v!),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Information
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Available Features:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            "• Basic recorder passthrough: ${ready ? "✓" : "✗"}",
                          ),
                          Text(
                            "• CrossCoder encoding: ${hasStandaloneEncoder ? "✓" : "✗"}",
                          ),
                          const Text("• Codec switching: ✗ (TODO)"),
                          const Text("• Auto-detection: ✗ (TODO)"),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}
