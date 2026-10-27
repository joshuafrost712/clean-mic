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

`setup.sh` also installs a small **supervisor** LaunchAgent
(`com.cleanmic.supervisor`) so the denoiser runs *only while you're dictating*
instead of holding the microphone 24/7. The supervisor watches your dictation
app's log; when a recording starts it launches MetalVoice, and after
`CLEANMIC_IDLE_SECONDS` (default 180) with no recording it quits MetalVoice and
releases the mic. This keeps the mic off when you're not dictating and avoids a
speaker↔mic feedback loop from a long-lived instance whose output can drift onto
the speakers across audio-device changes.

The supervisor keys on **Handy**'s log (`~/Library/Logs/com.pais.handy/handy.log`,
with Handy's `log_level` set to `debug`). The one tradeoff: MetalVoice
cold-launches in ~1-2s, so the first utterance after a long idle gap can clip
while it warms up; back-to-back dictation within the idle window stays warm. Set
`CLEANMIC_IDLE_SECONDS` in the LaunchAgent to tune the window. The executable
copy of the script lives at `~/Library/Application Support/cleanmic/` (not in
this repo) because macOS blocks launchd-spawned `bash` from reading scripts
inside `~/Documents`. To remove it:

```bash
launchctl bootout gui/$(id -u)/com.cleanmic.supervisor
rm ~/Library/LaunchAgents/com.cleanmic.supervisor.plist
pkill -f 'MetalVoice.app/Contents/MacOS/MetalVoice'
```

Important: in MetalVoice, set the Input to your physical mic BY NAME (e.g.
"MacBook Pro Microphone"), not "Default." Dictation apps often flip the system
default input to their chosen device; if MetalVoice follows "Default" it loops
onto BlackHole and goes silent. Pinning the input by name makes it immune.

## Troubleshooting

No audio reaching your dictation app? Work through these in order:

- Are you actually speaking? DeepFilterNet correctly suppresses a quiet room
  (or just fan/AC noise) to near-silence. No speech = no signal, by design.
- Is MetalVoice even running? With the supervisor it only runs *while you're
  dictating* and for `CLEANMIC_IDLE_SECONDS` after. Check with
  `pgrep -fl MetalVoice`. If it never starts when you record, the supervisor
  isn't seeing Handy's log markers: confirm Handy's `log_level` is `debug` and
  watch `tail -f /tmp/cleanmic-supervisor.out.log` while you dictate.
- Microphone permission: System Settings > Privacy & Security > Microphone,
  make sure MetalVoice is ON. This can drop after a reboot; toggling it and
  restarting MetalVoice fixes it. The supervisor launches the `.app` bundle
  (via `open`, not the raw binary) so the permission granted to the app carries
  over.
- In MetalVoice, confirm Input = your physical mic and Output = BlackHole 2ch,
  both pinned BY NAME (not "Default"). A "Default" output can resolve to your
  speakers and create a speaker↔mic feedback loop.
- Restart the whole thing cleanly (use this if audio ever drops, e.g. after
  plugging/unplugging headphones, which re-enumerates audio devices):

  ```bash
  pkill -f 'MetalVoice.app/Contents/MacOS/MetalVoice'; \
    launchctl kickstart -k gui/$(id -u)/com.cleanmic.supervisor
  ```

- Verify objectively whether your voice reaches BlackHole (talk during it):

  ```bash
  ffmpeg -f avfoundation -i ":$(ffmpeg -f avfoundation -list_devices true -i '' 2>&1 | \
    awk -F'[][]' '/BlackHole 2ch/{print $2; exit}')" -t 8 /tmp/bh.wav -y 2>/dev/null
  ffmpeg -i /tmp/bh.wav -af volumedetect -f null - 2>&1 | grep mean_volume
  ```
  A mean_volume well above the ~-85 dB silence floor means signal is flowing.

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
