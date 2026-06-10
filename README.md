# clean-mic

A local, free, real-time denoised microphone for dictation and calls on Apple
Silicon Macs. It removes steady background noise (fans, AC, wind, room echo) at
the source, before any app or speech-to-text model hears it.

## Why this exists

Local speech-to-text engines (Parakeet, Whisper) fall into a repetition loop,
repeating the same phrase 10+ times, when they receive noise-dominated audio.
The trigger is environmental: a fan running nearby, or working outdoors, picked
up by an omnidirectional built-in laptop mic. The model's decoder confidence
collapses on the noise and it loops.

The durable fix is to clean the audio at the source rather than tune the model.
A clean signal means no loop, in any app, for free.

## How it works

```
Built-in mic -> MetalVoice (DeepFilterNet3, real-time, Apple Neural Engine)
             -> BlackHole 2ch (virtual audio cable)
             -> VoiceInk / Zoom / Meet / any app
```

This repo is a thin wrapper: it vendors the released MetalVoice binary, installs
the BlackHole virtual cable, and documents the one-time routing. The heavy
lifting is done by two open-source projects (credited below).

## Install

```bash
./setup.sh
```

Then follow the printed one-time GUI steps (mic permission, device routing).
A reboot may be needed after installing BlackHole.

`setup.sh` also installs a LaunchAgent (`com.cleanmic.metalvoice`) that starts
MetalVoice at login and relaunches it if it ever quits, so the denoiser is
always running with nothing to remember. To remove it:

```bash
launchctl bootout gui/$(id -u)/com.cleanmic.metalvoice
rm ~/Library/LaunchAgents/com.cleanmic.metalvoice.plist
```

Important: in MetalVoice, set the Input to your physical mic BY NAME (e.g.
"MacBook Pro Microphone"), not "Default." Dictation apps often flip the system
default input to their chosen device; if MetalVoice follows "Default" it loops
onto BlackHole and goes silent. Pinning the input by name makes it immune.

## Credits / licenses

- MetalVoice (MIT) — https://github.com/Ghostkwebb/MetalVoice
- DeepFilterNet — https://github.com/Rikorose/DeepFilterNet
- BlackHole — https://github.com/ExistentialAudio/BlackHole

## Optional safety nets

If a loop ever still slips through on very loud noise, add either:
- a Silero VAD gate (https://github.com/snakers4/silero-vad) to force true
  silence on non-speech, or
- a repetition post-filter (collapse "phrase repeated N times" to one), e.g. via
  VoiceInk's AI Enhancement pointed at a local Ollama model.

## Requirements

Apple Silicon Mac (M1 or newer), macOS 13+, Homebrew. Intel Macs are not
supported by MetalVoice.
