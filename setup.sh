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

echo "==> 3/4  Installing the on-demand supervisor LaunchAgent"
# The supervisor runs MetalVoice ONLY while Handy is recording (it watches
# Handy's log) and releases the microphone after an idle gap, instead of an
# always-on denoiser holding the mic 24/7. This keeps the mic off when you're
# not dictating and avoids a speaker<->mic feedback loop from a long-lived
# instance whose output can drift onto the speakers across audio-device changes.
LABEL="com.cleanmic.supervisor"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
# Executable copy lives OUTSIDE ~/Documents: macOS TCC blocks launchd-spawned
# bash from reading a script inside the protected Documents folder.
SUP_DIR="$HOME/Library/Application Support/cleanmic"
mkdir -p "$HOME/Library/LaunchAgents" "$SUP_DIR"
install -m 0755 "$REPO_DIR/cleanmic-supervisor.sh" "$SUP_DIR/cleanmic-supervisor.sh"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>/bin/bash</string><string>$SUP_DIR/cleanmic-supervisor.sh</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>StandardOutPath</key><string>/tmp/cleanmic-supervisor.out.log</string>
    <key>StandardErrorPath</key><string>/tmp/cleanmic-supervisor.err.log</string>
</dict>
</plist>
PLISTEOF
# Migrate off the old always-on agent if it exists, then (re)load the supervisor.
launchctl bootout "gui/$(id -u)/com.cleanmic.metalvoice" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.cleanmic.metalvoice.plist"
pkill -f "MetalVoice.app/Contents/MacOS/MetalVoice" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" && launchctl enable "gui/$(id -u)/$LABEL" || true
echo "    Supervisor installed: $PLIST"
echo "    (to disable later: launchctl bootout gui/\$(id -u)/$LABEL && rm \"$PLIST\")"

# One-click recovery app: kills + relaunches the denoiser (re-grabs the mic).
APP_SRC="$REPO_DIR/Restart Clean-Mic.applescript"
if [ -f "$APP_SRC" ]; then
  APP_DEST="/Applications/Restart Clean-Mic.app"
  [ -w /Applications ] || { mkdir -p "$HOME/Applications"; APP_DEST="$HOME/Applications/Restart Clean-Mic.app"; }
  rm -rf "$APP_DEST"
  if osacompile -o "$APP_DEST" "$APP_SRC" 2>/dev/null; then
    echo "    One-click recovery app: $APP_DEST (drag it to your Dock)"
  fi
fi

echo "==> 4/4  Manual steps (GUI, one time):"
cat <<'STEPS'
    a. Open MetalVoice.app once (quarantine was cleared above) and grant it
       Microphone permission when prompted. After that the supervisor launches
       and quits it for you; you don't keep it open.
    b. In MetalVoice:   Input  = your built-in mic (exact CoreAudio name, e.g.
                                 "MacBook Pro Microphone")
                        Output = BlackHole 2ch
       Turn DeepFilterNet AI noise suppression ON. These settings persist and
       are re-applied each time the supervisor relaunches it.
    c. In your dictation app (Handy/VoiceInk): set the input device to
       "BlackHole 2ch". Leave System Settings > Sound > Input on your REAL mic,
       so only the dictation app depends on the pipeline (not your whole system).

    NOTE: pin MetalVoice's Input to the physical mic BY NAME (not "Default").
    Dictation apps often flip the system default input to their chosen device;
    if MetalVoice is on "Default" it then loops onto BlackHole and goes silent.
    Pin Output to "BlackHole 2ch" (not "Default") too: a "Default" output can
    resolve to your speakers and create a speaker<->mic feedback loop.

    The supervisor (step 3) handles when MetalVoice runs: it starts it when Handy
    begins recording and quits it after CLEANMIC_IDLE_SECONDS (default 180) of no
    recording, so the mic is released when you're not dictating. The supervisor
    keys on Handy's log markers and assumes Handy's log_level is "debug".

    Tip: list your exact CoreAudio device names with
         system_profiler SPAudioDataType | grep -E ':$'

    Verify: turn a fan on, dictate a few paragraphs. The repetition loop should be gone.
STEPS
echo "Done."
