# audio buffer fix

games under crossover crackle unless the output device runs at 88.2 or 96 khz, and bluetooth and most usb devices cannot. the sample rate was never the problem. the buffer length is, and that can be fixed at any rate.

## symptom

crackle in game audio and a choppy microphone in voice chat. the usual advice is to set the device to 96 khz in audio midi setup. a bluetooth headset offers 44.1 khz only, a usb microphone 44.1 or 48.

## cause

wine wakes the game every 10 ms and the engine keeps one or two such periods queued. coreaudio pulls 512 frames per io cycle: 11.6 ms at 44.1 khz, 10.7 ms at 48 khz. that is longer than one period, so the queue runs dry and wine pads the gap with silence. at 96 khz the same 512 frames last 5.3 ms and the queue never empties.

capture has the mirror problem: wine hands out one 10 ms packet per io cycle and drops the surplus.

## measurement

a probe that plays and records the way sdl does, 15 s per run. playback counts inserted silence, capture counts missing audio.

| device | stock | fixed |
|---|---|---|
| bluetooth headset, 44.1 khz | 6.0–6.3 % | 0.1 % |
| usb output, 48 khz | 1.8–2.2 % | 0.1–0.2 % |
| built-in speakers, 48 khz | 1.8–2.2 % | 0.0–0.1 % |
| built-in speakers, 96 khz | 0.1 % | n/a |
| usb microphone, 48 khz | 6.9 % | 0.2 % |
| usb microphone, 44.1 khz | 6.4 % | 0.1 % |

```bars
silence inserted, bluetooth headset | % | 6.3 | 0.1
```

setting the microphone to 44.1 khz, the other half of the usual advice, did not help: 44.1 khz lost as much as 48.

## the fix

the io buffer size is a per-process setting, so it has to be set from inside the game. a wrapper replaces wine's `winecoreaudio.so`, re-exports the real driver, and on load asks coreaudio for a 5.33 ms buffer on every device: 256 frames at 48 khz, 235 at 44.1.

```c coreaudio_iobuf.c
Float64 hz;                          // the device's current rate
UInt32 frames = hz * io_ms / 1000;   // 5.33 ms at any rate
AudioObjectSetPropertyData(device, &buffer_frame_size,
                           0, NULL, sizeof frames, &frames);
```

## what changes on disk

- `lib/wine/x86_64-unix/winecoreaudio.so` becomes the wrapper
- `winecoreaudio.so.orig` is the untouched original
- `winecoreaudio_real.so` is the copy the wrapper loads
- `mgf_audio_io_ms` holds the buffer length: wine processes are started by crossover, so there is no environment to pass it through

## limits

- applies to wine processes started after the change. restart steam and the game.
- if a bluetooth headset's own microphone is the input, macos drops the headset to 16 khz mono. no buffer setting fixes that. pick another microphone under audio devices.
- `audio io buffer` in settings changes the length. 0 restores coreaudio's default.
