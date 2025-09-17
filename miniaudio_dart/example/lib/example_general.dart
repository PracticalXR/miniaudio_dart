// ignore_for_file: avoid_print

import "dart:async";
import "dart:typed_data";
import "package:flutter/material.dart";
import "package:miniaudio_dart/miniaudio_dart.dart";
import "package:miniaudio_dart/miniaudio_flutter.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    title: "MiniaudioDart General Example",
    home: ExamplePage(),
  ));
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});
  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  final engine = Engine();
  var loopDelay = 0.0;
  late Recorder recorder;
  Timer? recorderTimer;
  Timer? generatorTimer;
  late Generator generator;
  late StreamPlayer streamPlayer;
  bool _streamInit = false;
  WaveformType waveformType = WaveformType.sine;
  NoiseType noiseType = NoiseType.white;
  bool enableWaveform = false;
  bool enableNoise = false;
  bool enablePulse = false;
  var pulseDelay = 0.25;
  final List<Float32List> recordingBuffer = [];
  final List<Float32List> generatorBuffer = [];
  bool _monitorMuted = false;
  double _monitorVolume = 1.0;
  bool _monitorEnabled = false;
  int totalRecordedFrames = 0;
  final List<Sound> sounds = [];
  late final Future<Sound> soundFuture;
  List<(String name, bool isDefault)> _playbackDevices = const [];
  int _selectedPlaybackIndex = 0;

  @override
  void initState() {
    super.initState();
    soundFuture = _initializeSound();
    engine
        .playbackDeviceChanges(interval: const Duration(seconds: 2))
        .listen((list) {
      setState(() {
        _playbackDevices = list;
        if (_selectedPlaybackIndex >= list.length ||
            _selectedPlaybackIndex < 0) {
          _selectedPlaybackIndex = list.indexWhere((e) => e.$2);
          if (_selectedPlaybackIndex < 0) _selectedPlaybackIndex = 0;
        }
      });
    });
  }

  Future<Sound> _initializeSound() async {
    if (!engine.isInit) {
      await engine.init();
      recorder = Recorder();
      generator = Generator();
      streamPlayer = StreamPlayer(mainEngine: engine);
      await streamPlayer.init(channels: 1, sampleRate: 48000, bufferMs: 120);
      streamPlayer.start();
      _monitorEnabled = true;
    }
    return engine.loadSoundAsset("assets/laser_shoot.wav");
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("General Example")),
        body: Center(
          child: FutureBuilder(
            future: soundFuture,
            builder: (_, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const CircularProgressIndicator();
              }
              if (!snapshot.hasData) {
                return Text("Error: ${snapshot.error}");
              }
              final sound = snapshot.data as Sound;
              return SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    const Text("Sound Playback",
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    ElevatedButton(
                      onPressed: () async {
                        await engine.start();
                        sound.play();
                      },
                      child: const Text("PLAY"),
                    ),
                    ElevatedButton(
                        onPressed: () => sound.pause(),
                        child: const Text("PAUSE")),
                    ElevatedButton(
                        onPressed: () => sound.stop(),
                        child: const Text("STOP")),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Volume:"),
                        SizedBox(
                          width: 200,
                          child: Slider(
                            value: sound.volume,
                            min: 0,
                            max: 10,
                            divisions: 20,
                            label: sound.volume.toStringAsFixed(2),
                            onChanged: (v) => setState(() => sound.volume = v),
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await engine.start();
                        sound.playLooped(
                            delay: Duration(
                                milliseconds: (loopDelay * 1000).toInt()));
                      },
                      child: const Text("PLAY LOOPED"),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Loop delay:"),
                        SizedBox(
                          width: 200,
                          child: Slider(
                            value: loopDelay,
                            min: 0,
                            max: 7,
                            divisions: 300,
                            label: loopDelay.toStringAsFixed(2),
                            onChanged: (v) => setState(() => loopDelay = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text("Recorder",
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    ElevatedButton(
                      child: Text(recorder.isRecording
                          ? "STOP RECORDING"
                          : "START RECORDING"),
                      onPressed: () async {
                        if (recorder.isRecording) {
                          setState(() => recorder.stop());
                          try {
                            streamPlayer.stop();
                          } catch (_) {}
                          recorderTimer?.cancel();
                          recordingBuffer.clear();
                          totalRecordedFrames = 0;
                        } else {
                          if (!recorder.isInit) {
                            await recorder.initStream(
                                sampleRate: 48000,
                                channels: 1,
                                format: AudioFormat.float32);
                            recorder.isInit = true;
                          }
                          if (!_streamInit) {
                            await streamPlayer.init(
                              format: AudioFormat.float32,
                              channels: recorder.channels,
                              sampleRate: recorder.sampleRate,
                              bufferMs: 240,
                            );
                            _streamInit = true;
                          }
                          await engine.start();
                          streamPlayer.start();
                          setState(() => recorder.start());
                          recorderTimer = Timer.periodic(
                              const Duration(milliseconds: 50),
                              (_) => accumulateRecorderFrames());
                          totalRecordedFrames = 0;
                          if (!_monitorEnabled) {
                            await recorder.enableMonitoring(streamPlayer);
                            _monitorEnabled = true;
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text("Generator",
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Waveform Type:"),
                        DropdownButton<WaveformType>(
                          value: waveformType,
                          items: WaveformType.values
                              .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.toString().split(".").last)))
                              .toList(),
                          onChanged: enableWaveform
                              ? (v) {
                                  setState(() => waveformType = v!);
                                  generator.setWaveform(
                                      waveformType, 432.0, 0.5);
                                  if (enablePulse)
                                    generator.setPulsewave(
                                        432.0, 0.5, pulseDelay);
                                }
                              : null,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Noise Type:"),
                        DropdownButton<NoiseType>(
                          value: noiseType,
                          items: NoiseType.values
                              .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.toString().split(".").last)))
                              .toList(),
                          onChanged: enableNoise
                              ? (v) {
                                  setState(() => noiseType = v!);
                                  generator.setNoise(noiseType, 0, 0.5);
                                }
                              : null,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: enableWaveform,
                          onChanged: (v) {
                            setState(() => enableWaveform = v!);
                            generator.setWaveform(waveformType, 432.0, 0.5);
                          },
                        ),
                        const Text("Waveform"),
                        const SizedBox(width: 20),
                        Checkbox(
                          value: enableNoise,
                          onChanged: (v) {
                            setState(() => enableNoise = v!);
                            generator.setNoise(noiseType, 0, 0.5);
                          },
                        ),
                        const Text("Noise"),
                        const SizedBox(width: 20),
                        Checkbox(
                          value: enablePulse,
                          onChanged: (v) {
                            setState(() => enablePulse = v!);
                            generator.setPulsewave(432.0, 0.5, pulseDelay);
                          },
                        ),
                        const Text("Pulse"),
                      ],
                    ),
                    ElevatedButton(
                      child: Text(generator.isGenerating ? "STOP" : "START"),
                      onPressed: () async {
                        if (generator.isGenerating) {
                          setState(() {
                            generator.stop();
                            generatorTimer?.cancel();
                          });
                        } else {
                          if (!generator.isInit) {
                            await generator.init(
                                AudioFormat.float32, 2, 48000, 5);
                            generator.setWaveform(WaveformType.sine, 432, 0.5);
                            setState(() => generator.isInit = true);
                          }
                          setState(() {
                            generator.start();
                            generatorTimer = Timer.periodic(
                                const Duration(milliseconds: 100),
                                (_) => accumulateGeneratorFrames());
                          });
                        }
                      },
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Pulse delay:"),
                        SizedBox(
                          width: 200,
                          child: Slider(
                            value: pulseDelay,
                            min: 0,
                            max: 1,
                            divisions: 300,
                            label: pulseDelay.toStringAsFixed(2),
                            onChanged: (v) => setState(() => pulseDelay = v),
                            onChangeEnd: (_) =>
                                generator.setPulsewave(432.0, 0.5, pulseDelay),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Monitor volume"),
                        SizedBox(
                          width: 240,
                          child: Slider(
                            value: _monitorMuted ? 0.0 : _monitorVolume,
                            min: 0.0,
                            max: 100.0,
                            onChanged: (v) {
                              setState(() {
                                _monitorVolume = v;
                                _monitorMuted = v == 0.0;
                              });
                              try {
                                streamPlayer.volume = v;
                              } catch (_) {}
                            },
                          ),
                        ),
                        IconButton(
                          icon: Icon(_monitorMuted
                              ? Icons.volume_off
                              : Icons.volume_up),
                          onPressed: () {
                            setState(() => _monitorMuted = !_monitorMuted);
                            try {
                              streamPlayer.volume =
                                  _monitorMuted ? 0.0 : _monitorVolume;
                            } catch (_) {}
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  void accumulateRecorderFrames() {
    if (!recorder.isRecording) return;
    final framesAvail = recorder.getAvailableFrames();
    if (framesAvail <= 0) return;
    final chunk = recorder.readChunk(maxFrames: framesAvail);
    if (chunk.isNotEmpty) {
      recordingBuffer.add(chunk);
      totalRecordedFrames += (chunk.length ~/ recorder.channels);
      if (_monitorEnabled) {
        try {
          streamPlayer.writeFloat32(chunk);
        } catch (_) {}
      }
    }
  }

  void accumulateGeneratorFrames() {
    if (generator.isGenerating) {
      final frames = generator.getAvailableFrames();
      final buffer = generator.getBuffer(frames);
      if (buffer.isNotEmpty) {
        generatorBuffer.add(buffer);
        totalRecordedFrames += frames;
      }
    }
  }

  @override
  void dispose() {
    recorder.dispose();
    generator.dispose();
    try {
      streamPlayer.dispose();
    } catch (_) {}
    super.dispose();
  }
}
