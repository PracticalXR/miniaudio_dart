# miniaudio_dart

A implementation for miniaudio supporting native and web platforms.

[![pub package](https://img.shields.io/pub/v/miniaudio_dart.svg)](https://pub.dev/packages/miniaudio_dart)

---

## Web setup

Include the loader (do NOT defer) in `web/index.html`:

```html
<script src="assets/packages/miniaudio_dart_web/js/miniaudio_dart_web.loader.js"></script>
```

Inside the onload bootstrap add:

```js
await _miniaudio_dart.loader.load();
```

This package uses SharedArrayBuffer; enable cross‑origin isolation:

- Cross-Origin-Opener-Policy: same-origin
- Cross-Origin-Embedder-Policy: require-corp

---

## Core concepts

| Component      | Purpose |
| -------------- | ------- |
| Engine         | Playback device + sound management |
| Sound          | Decoded or raw PCM (supports loop + loop delay) |
| StreamPlayer   | Low latency push of Float32 interleaved frames |
| Recorder       | Capture microphone to ring buffer or file |
| Generator      | Procedural waveform / noise source |

---

## New / changed APIs (device + stream management)

### Playback (output) devices

```dart
await engine.enumeratePlaybackDevices();                // List (name,isDefault)
await engine.selectPlaybackDeviceByIndex(index);        // Switch (invalidates sounds)
await engine.switchPlaybackDevice(index);               // Simple convenience
await engine.switchPlaybackDeviceAndRebuild(index);     // Rebind loaded sounds
await engine.switchPlaybackDevicePreservingMonitoring(
  index: index,
  monitorPlayer: streamPlayer,
  recorder: recorder,
  rebindSounds: true,
);
engine.playbackDeviceChanges().listen(...);             // Polling stream
```

Notes:

- Raw switch invalidates existing native sound objects; use one of the “switch*AndRebuild / PreservingMonitoring” helpers for transparent recovery.
- StreamPlayers are recreated internally when using `switchPlaybackDevicePreservingMonitoring`.
- Web: enumeration returns a single logical “Default Output”; switching is a no‑op.

### Capture (input) devices

```dart
await recorder.enumerateInputDevices();                 // List (name,isDefault)
await recorder.switchInputDevicePreservingStream(index);// Minimal interruption
recorder.inputDeviceChanges().listen(...);              // Polling stream
```

Notes:

- Switching input preserves ring buffer when format/channels unchanged.
- Web: single “Default Input”; switching is a no‑op.

### Monitoring (record → playback)

```dart
await recorder.initStream(sampleRate: 48000, channels: 1);
recorder.start();

final monitor = StreamPlayer(mainEngine: engine);
await recorder.enableMonitoring(monitor);
monitor.volume = 0.8;
```

When switching only output device:

```dart
await engine.switchPlaybackDevicePreservingMonitoring(
  index: newIdx,
  recorder: recorder,
  monitorPlayer: monitor,
  rebindSounds: true,
);
```

Recorder keeps capturing; monitor player is rebuilt quickly.

### Sound looping

```dart
sound.playLooped(delay: Duration(milliseconds: 500));
sound.stop();   // Resets position (loop delay cleared)
sound.pause();  // Keeps position (loop disabled)
```

### Rebinding sounds after device change

Performed automatically by:

- `switchPlaybackDeviceAndRebuild`
- `switchPlaybackDevicePreservingMonitoring (rebindSounds: true)`

Web implementation is a no‑op (single logical device).

---

## Quick usage snippets

### Engine + Sound

```dart
final engine = Engine();
await engine.init();    // optional periodMs arg
await engine.start();

final audioData = AudioData(bytes: myUint8List); // Provide decoded or encoded data
final sound = await engine.loadSound(audioData);

sound.volume = 0.5;
sound.playLooped(delay: Duration(seconds: 1));
await Future.delayed(Duration(seconds: 3));
sound.stop();
```

### Enumerate & switch output (with rebuild)

```dart
final devices = await engine.enumeratePlaybackDevices();
for (var i=0; i<devices.length; i++) {
  print('$i: ${devices[i].$1}${devices[i].$2 ? " (default)" : ""}');
}
await engine.switchPlaybackDeviceAndRebuild(targetIndex);
```

### Recorder streaming + monitoring

```dart
final recorder = Recorder(mainEngine: engine);
await recorder.initStream(sampleRate: 48000, channels: 1);
recorder.start();

final monitor = StreamPlayer(mainEngine: engine);
await recorder.enableMonitoring(monitor);

recorder.stream(intervalMs: 20).listen((chunk) {
  // chunk = Float32List interleaved frames
});
```

### Switch input device seamlessly

```dart
final inputs = await recorder.enumerateInputDevices();
await recorder.switchInputDevicePreservingStream(newIndex);
```

---

## Streams & polling

Device change polling (output):

```dart
engine.playbackDeviceChanges(interval: Duration(seconds: 2))
  .listen((list) => print('Playback devices updated: $list'));
```

Input devices:

```dart
recorder.inputDeviceChanges().listen((list) {
  print('Input devices: $list');
});
```

---

## Limitations / platform notes

- Output device switch requires rebuilding native `ma_engine`; helpers wrap rebind/recreate.
- StreamPlayer currently supports only `AudioFormat.float32`.
- Format / channel changes during input switch are not auto‑negotiated (stop + re‑init required).
- Web: real multi‑device selection not available; APIs return single logical devices; rebind is no‑op.
- Loop delay not accounted in `Sound.duration`.

---

## Generator example

```dart
final generator = Generator();
await generator.initEngine();
await generator.init(AudioFormat.float32, 2, 48000, 5);

generator.setWaveform(WaveformType.sine, 440.0, 0.4);
generator.start();

generator.stream(chunkSizeMs: 50).listen((buf) {
  // Process Float32 samples
});
```

---

## Building

```bash
git submodule update --init --recursive
cd miniaudio_dart_ffi/src/build
# Web
emcmake cmake ..
cmake --build .
# Native (clean build)
rm -rf *
cmake ..
cmake --build .
```

Regenerate bindings:

```bash
cd ../../..
dart run ffigen
```

---

## TODO

- [x] Sound loop clarity
- [x] Playback device enumeration / switching
- [x] Input device enumeration / seamless switching
- [x] Stream monitoring preservation on output switch
- [ ] Graceful handling when no devices present

---

## Troubleshooting

| Issue | Cause | Fix |
| ----- | ----- | --- |
| Silence after output switch | Not using rebuild helper | Use `switchPlaybackDeviceAndRebuild` |
| Recorder stops after output switch | Old manual teardown | Use `switchPlaybackDevicePreservingMonitoring` |
| Web start exception (autoplay) | No user gesture | Call `engine.start()` after user interaction |
| Access violation native | Pointer size mismatch (old FFI) | Rebuild + update binding functions |

---

## License

(Keep original license notice here if applicable.)
