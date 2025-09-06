(function (g) {
  g.Module = g.Module || {};
  g.miniaudio = g.miniaudio || {};
  // Make a global var binding visible to EM_ASM (bare identifier)
  // eslint-disable-next-line no-var
  var miniaudio = g.miniaudio;

  // Keep Module.miniaudio pointing at the same object
  g.Module.miniaudio = g.Module.miniaudio || miniaudio;

  // Precreate objects the glue reads
  miniaudio.playback = miniaudio.playback || {};
  g.Module.miniaudioProcessorOptions = g.Module.miniaudioProcessorOptions || {};

  // Unlock hook used from native glue
  miniaudio.unlock = miniaudio.unlock || (async function () {
    try {
      const ctx = (g.Module.SDL && g.Module.SDL.audioContext)
        ? g.Module.SDL.audioContext
        : (g.AudioContext ? new g.AudioContext() : null);
      if (ctx && ctx.state === "suspended") await ctx.resume();
    } catch (_) {}
  });
})(typeof window !== "undefined" ? window : self);