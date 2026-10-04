// coreaudio_iobuf.c — takes the place of Wine's winecoreaudio.so and re-exports the real one
// (winecoreaudio_real.so), so it runs inside every Wine process that plays or records audio.
//
// Wine's WASAPI wakes the game every 10 ms, and SDL (Source 2) keeps only one or two of those
// periods queued. CoreAudio meanwhile pulls 512 frames at a time: 11.6 ms of audio at 44.1 kHz,
// 10.7 ms at 48 kHz. Each pull that finds less than that in the queue is padded with silence,
// which is the crackle. At 88.2/96 kHz the same 512 frames are only 5.3-5.8 ms and it goes away,
// hence the "set the device to 96 kHz" advice, which Bluetooth and many USB devices cannot follow.
// Capture has the mirror problem: one 10 ms packet per IO cycle, the surplus is dropped (6-7 % of the mic).
//
// Fix: ask CoreAudio for the 96 kHz IO buffer *duration* at whatever rate the device runs.
// The IO buffer size is a per-process setting, so it has to be done here, inside the game process.
//
// env: COREAUDIO_IO_MS  IO buffer length in ms (default 5.33; 0 = leave CoreAudio's default)
//
// file: mgf_audio_io_ms, next to this library, holds the same number. Wine processes are started by
//       CrossOver, so the app has no environment to pass it through; the variable wins if both exist.
//
// build: make payload (links with -reexport_library against a stub named winecoreaudio_real.so;
//        on the user's machine that name is an untouched copy of the real driver)
#include <CoreAudio/CoreAudio.h>
#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static double io_ms = 512 * 1000.0 / 96000;

static const AudioObjectPropertyAddress
    devices = {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
    rate = {kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
    buffer = {kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};

static OSStatus apply(AudioObjectID object, UInt32 count, const AudioObjectPropertyAddress *changed, void *context) {
    AudioDeviceID ids[64];
    UInt32 size = sizeof ids;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &devices, 0, NULL, &size, ids)) return noErr;
    for (UInt32 i = 0; i < size / sizeof ids[0]; i++) {
        Float64 hz = 0;
        UInt32 n = sizeof hz;
        if (AudioObjectGetPropertyData(ids[i], &rate, 0, NULL, &n, &hz) || hz <= 0) continue;
        UInt32 frames = (UInt32)(hz * io_ms / 1000);
        AudioObjectSetPropertyData(ids[i], &buffer, 0, NULL, sizeof frames, &frames);  // clamped by the HAL
        // a device changing its rate (Bluetooth A2DP <-> headset mode) needs a new frame count
        AudioObjectRemovePropertyListener(ids[i], &rate, apply, NULL);
        AudioObjectAddPropertyListener(ids[i], &rate, apply, NULL);
    }
    return noErr;
}

static void read_conf(void) {
    Dl_info me;
    char path[PATH_MAX];
    if (!dladdr(read_conf, &me) || !me.dli_fname) return;
    const char *slash = strrchr(me.dli_fname, '/');
    if (!slash) return;
    if (snprintf(path, sizeof path, "%.*s/mgf_audio_io_ms", (int)(slash - me.dli_fname), me.dli_fname) >= (int)sizeof path) return;
    FILE *f = fopen(path, "r");
    if (!f) return;
    double ms;
    if (fscanf(f, "%lf", &ms) == 1) io_ms = ms;
    fclose(f);
}

__attribute__((constructor)) static void init(void) {
    const char *s = getenv("COREAUDIO_IO_MS");
    if (s) io_ms = atof(s);
    else read_conf();
    if (io_ms <= 0) return;
    apply(0, 0, NULL, NULL);
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &devices, apply, NULL);  // devices that appear later
}
