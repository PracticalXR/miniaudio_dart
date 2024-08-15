# miniaudio_dart

WIP forked from https://github.com/MichealReed/minisound/pull/6, original credit for Engine and Sound implementations and brilliant cross-platform lib interface go to MichealReed.

## Getting started on the web

While the main script is quite large, there are a loader script provided. Include it in the `web/index.html` file like this

```html
  <script src="assets/packages/miniaudio_dart_web/js/miniaudio_dart_web.loader.js"></script>
```

> It is highly recommended NOT to make the script `defer`, as loading may not work properly. Also, it is very small (only 18 lines).

And at the bottom, at the body's `<script>` do like this

```js
window.addEventListener(
  'load',
  // ADD 'async'
  async function (ev) {
      // ADD THIS LINE AT THE TOP
      await _miniaudio_dart.loader.load();

      // LEAVE THE REST IN PLACE
      // Download main.dart.js
      _flutter.loader.loadEntrypoint({
        serviceWorker: {
          serviceWorkerVersion: serviceWorkerVersion
        },
        onEntrypointLoaded: function (engineInitializer) {
          engineInitializer.initializeEngine().then(function (appRunner) {
            appRunner.runApp();
          });
        }
      });
    }
  );
```

`MiniaudioDart` uses `SharedArrayBuffer` feature, so you should [enable cross-origin isolation on your site](https://web.dev/cross-origin-isolation-guide/).

## Usage

To use this plugin, add `miniaudio_dart` as a [dependency in your pubspec.yaml file](https://flutter.dev/platform-plugins/).

```dart
import "package:miniaudio_dart/miniaudio_dart.dart" as miniaudio_dart;

void main() {
  final engine = miniaudio_dart.Engine();

  // this method takes an update period in milliseconds as an argument, which
  // determines the length of the latency (does not currently affect the web)
  await engine.init(); 

  // there is also a 'loadSound' method to load a sound from the Uint8List
  final sound = await engine.loadSoundAsset("asset/path.ext");
  sound.volume = 0.5;

  // this may cause a MiniaudioDartPlatformException to be thrown on the web
  // before any user interaction due to the autoplay policy
  await engine.start(); 

  sound.play();

  await Future.delayed(sound.duration*.5);

  sound.pause(); // this method saves sound position
  sound.stop(); // but this does not

  final loopDelay=Duratoin(seconds: 1);
  sound.playLooped(delay: loopDelay); // sound will be looped with one second period

  await Future.delayed((sound.duration + loopDelay) * 5); // sound duration does not account loop delay

  sound.stop();

  // it is recommended to unload sounds manually to prevent memory leaks
  sound.unload(); 

  // the engine and all loaded sounds will be automatically disposed when 
  // engine gets garbage-collected
}
```

### Recorder Example

```dart
import "package:miniaudio_dart/miniaudio_dart.dart" as miniaudio_dart;

void main() async {
  final recorder = miniaudio_dart.Recorder();

  // Initialize the recorder's engine
  await recorder.initEngine();

  // Initialize the recorder for streaming
  await recorder.initStream(
    sampleRate: 48000,
    channels: 1,
    format: miniaudio_dart.AudioFormat.float32,
    bufferDurationSeconds: 5,
  );

  // Start recording
  recorder.start();

  // Wait for some time while recording
  await Future.delayed(Duration(seconds: 5));

  // Stop recording
  recorder.stop();

  // Get the recorded buffer
  final buffer = recorder.getBuffer(recorder.getAvailableFrames());

  // Process the recorded buffer as needed
  // ...

  // Dispose of the recorder resources
  recorder.dispose();
}
```

### Generator Example

```dart
import "package:miniaudio_dart/miniaudio_dart.dart" as miniaudio_dart;

void main() async {
  final generator = miniaudio_dart.Generator();

  // Initialize the generator's engine
  await generator.initEngine();

  // Initialize the generator
  await generator.init(
    miniaudio_dart.AudioFormat.float32,
    2,
    48000,
    5,
  );

  // Set the waveform type, frequency, and amplitude
  generator.setWaveform(miniaudio_dart.WaveformType.sine, 440.0, 0.5);

  // Set the noise type, seed, and amplitude
  generator.setNoise(miniaudio_dart.NoiseType.white, 0, 0.2);

  // Start the generator
  generator.start();

  // Generate and process audio data in a loop
  while (true) {
    final available = generator.getAvailableFrames();
    final buffer = generator.getBuffer(available);

    // Process the generated buffer as needed
    // ...

    await Future.delayed(Duration(milliseconds: 100));
  }

  // Stop the generator
  generator.stop();

  // Dispose of the generator resources
  generator.dispose();
}
```

## Building the project

A Makefile is provided with recipes to build the project and ease development. Type `make help` to see a list of available commands.

To manually build the project, follow these steps:

1. Initialize the submodules:

   ```bash
   git submodule update --init --recursive
   ```

2. Make and/or Navigate to the `miniaudio_dart_ffi/src/build` directory:

   ```bash
   cd miniaudio_dart_ffi/src/build
   ```

3. Run the following commands to build the project using emcmake and cmake:

   ```bash
   emcmake cmake ..
   cmake --build .
   ```

   If you want to build the native version, encounter issues or want to start fresh, clean the `build` folder and rerun the cmake commands:

    ```bash
    rm -rf *
    cmake ..
    cmake --build .
    ```

4. For development work, it's useful to run `ffigen` from the `miniaudio_dart_ffi` directory:

   ```bash
   cd miniaudio_dart_ffi
   dart run ffigen
   ```

## TODO

- [x] Fix non-intuitiveness of pausing and stopping, then playing again looped sounds
- [x] Exclude emscripten build cache from git.
- [ ] Stop crash when no devices found for playback or capture
- [ ] Extract buffer stuff to unified AV Buffer packages dart and C.
- [ ] Automate local web deployment with strict origin flags for local testing.
- [x] Create a makefile.
- [ ] Document dependencies for building.
- [ ] Switch engine init to state machine.
