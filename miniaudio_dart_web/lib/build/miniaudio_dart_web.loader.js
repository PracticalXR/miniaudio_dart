if (!_miniaudio_dart) var _miniaudio_dart = {};
if (!_miniaudio_dart.loader) _miniaudio_dart.loader = {};

_miniaudio_dart.loader.load = function () {
    return new Promise(
        (resolve, reject) => {
            const miniaudio_dart_web_js = document.createElement("script");
            miniaudio_dart_web_js.src = "assets/packages/miniaudio_dart_web/build/miniaudio_dart_web.js";
            miniaudio_dart_web_js.onerror = reject;
            miniaudio_dart_web_js.onload = () => {
                if (runtimeInitialized) resolve();
                Module.onRuntimeInitialized = resolve;
            };
            document.head.append(miniaudio_dart_web_js);
        }
    );
}
