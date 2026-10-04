# audio devices

wine follows the macos default devices. this card sets them without a trip to system settings and keeps a bluetooth headset from quietly becoming the microphone.

## what it does

- sets the system output device
- sets the system input device
- sets the input volume of the chosen microphone

## how it works

all three are coreaudio properties: two on the system object, one on the device. the lists refresh when a device connects or the default changes.

```c CoreAudio
kAudioHardwarePropertyDefaultOutputDevice   // output
kAudioHardwarePropertyDefaultInputDevice    // microphone
kAudioDevicePropertyVolumeScalar            // input volume, input scope
```

## the bluetooth trap

when a bluetooth headset connects, macos often makes its microphone the default input. the first app that opens that microphone switches the headset to its 16 khz mono call profile, and game audio turns to phone quality. the card warns when the selected input is a bluetooth device.

## limits

- some devices have no software input volume. the slider is hidden for those.
- macos may switch devices again when a headset reconnects. the card shows the change but does not undo it.
