#!/usr/bin/env bash
#
# clean-mic setup
# Builds a local, free, real-time denoised microphone for dictation (VoiceInk,
# Zoom, Meet, anything). Removes fans / AC / wind at the source so speech-to-text
# models stop falling into repetition loops.
#
# Pipeline:  built-in mic -> MetalVoice (DeepFilterNet3) -> BlackHole 2ch -> your app
#
# Requirements: Apple Silicon Mac (M1 or newer), Homebrew.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$REPO_DIR/vendor"
METALVOICE_URL="https://github.com/Ghostkwebb/MetalVoice/releases/download/v1.1/MetalVoice_v1.1.zip"

echo "==> 1/3  Installing BlackHole 2ch virtual audio cable (asks for your admin password)"
if brew list blackhole-2ch >/dev/null 2>&1; then
  echo "    already installed."
else
  brew install blackhole-2ch
  echo "    NOTE: a reboot may be required before BlackHole appears in audio device lists."
fi

echo "==> 2/3  Fetching MetalVoice (DeepFilterNet3 denoiser)"
mkdir -p "$VENDOR_DIR"
if [ ! -d "$VENDOR_DIR/MetalVoice.app" ]; then
  curl -sL -o "$VENDOR_DIR/MetalVoice_v1.1.zip" "$METALVOICE_URL"
  ( cd "$VENDOR_DIR" && unzip -oq MetalVoice_v1.1.zip )
fi
# MetalVoice is open source and ad-hoc signed (not notarized). Clearing the
# download quarantine lets it launch without a Gatekeeper "damaged/blocked"
# dialog. Remove this line if you prefer to approve it via System Settings.
xattr -dr com.apple.quarantine "$VENDOR_DIR/MetalVoice.app" 2>/dev/null || true
echo "    MetalVoice.app -> $VENDOR_DIR/MetalVoice.app (quarantine cleared)"

echo "==> 3/4  Installing auto-start LaunchAgent (starts at login, self-heals)"
LABEL="com.cleanmic.metalvoice"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$VENDOR_DIR/MetalVoice.app/Contents/MacOS/MetalVoice"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$BIN</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>ProcessType</key><string>Interactive</string>
    <key>StandardOutPath</key><string>/tmp/cleanmic-metalvoice.out.log</string>
    <key>StandardErrorPath</key><string>/tmp/cleanmic-metalvoice.err.log</string>
</dict>
</plist>
PLISTEOF
# take over any hand-launched instance, then (re)load the agent
pkill -f "MetalVoice.app/Contents/MacOS/MetalVoice" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" && launchctl enable "gui/$(id -u)/$LABEL" || true
echo "    LaunchAgent installed: $PLIST"
echo "    (to disable later: launchctl bootout gui/\$(id -u)/$LABEL && rm \"$PLIST\")"

echo "==> 4/4  Manual steps (GUI, one time):"
cat <<'STEPS'
    a. Open MetalVoice.app (quarantine was cleared above, so it launches directly).
       Grant it Microphone permission when prompted.
    b. In MetalVoice:   Input  = your built-in mic (exact CoreAudio name, e.g.
                                 "MacBook Pro Microphone")
                        Output = BlackHole 2ch
       Turn DeepFilterNet AI noise suppression ON.
    c. In your dictation app (VoiceInk): set the input device to "BlackHole 2ch".
       Leave System Settings > Sound > Input on your REAL mic, so only the
       dictation app depends on the pipeline (not your whole system).

    NOTE: pin MetalVoice's Input to the physical mic BY NAME (not "Default").
    Dictation apps often flip the system default input to their chosen device;
    if MetalVoice is on "Default" it then loops onto BlackHole and goes silent.
    Auto-start at login is already handled by the LaunchAgent (step 3).

    Tip: list your exact CoreAudio device names with
         system_profiler SPAudioDataType | grep -E ':$'

    Verify: turn a fan on, dictate a few paragraphs. The repetition loop should be gone.
STEPS
echo "Done."
