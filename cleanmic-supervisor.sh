#!/usr/bin/env bash
#
# clean-mic supervisor
#
# Runs MetalVoice ONLY while you are dictating, instead of 24/7. It watches
# Handy's log; when Handy starts a recording it launches MetalVoice (so the
# denoised mic -> BlackHole -> Handy pipeline is live), and it quits MetalVoice
# after IDLE_SECONDS with no recording, releasing the microphone.
#
# Why a supervisor and not a per-keystroke tie: MetalVoice has no URL or IPC
# control, only launch/quit. Launching it cold takes ~1-3s, so binding it to the
# exact record keypress would clip the first word. Following Handy's activity
# with a short idle window keeps the mic off when you're not dictating while
# keeping back-to-back dictation warm. Only the first utterance after a long
# gap is cold.
#
# Kill path:  launchctl bootout gui/$(id -u)/com.cleanmic.supervisor
# Logs:       /tmp/cleanmic-supervisor.out.log

set -uo pipefail

# How long MetalVoice stays warm after the last recording stops, in seconds.
# Lower = mic released sooner; higher = fewer cold first-words during a session.
IDLE_SECONDS="${CLEANMIC_IDLE_SECONDS:-180}"

# Absolute paths (not derived from this script's location): the executable copy
# of this script lives under ~/Library/Application Support/cleanmic so launchd
# can read it (macOS TCC blocks launchd-spawned bash from reading ~/Documents).
#
# 2026-10-29: run MetalVoiceCLI, not MetalVoice.app. The app forgets its devices
# on every launch (it came up on BlackHole 16ch in Passthrough) and, even when
# set by hand to BlackHole 2ch with the AI on, sent pure silence. The CLI pins
# both devices by name and passed a speech test. A bare CLI started by launchd
# gets no mic access (macOS feeds it zeros), so setup.sh wraps it with its model
# in CleanMicCLI.app (bundle id com.cleanmic.cli), which holds its own mic
# permission. Its binary is run directly: launched via `open` it sent silence
# even with the grant on.
MV_BUNDLE="$HOME/Library/Application Support/cleanmic/CleanMicCLI.app"
MV_IN="${CLEANMIC_INPUT:-MacBook Pro Microphone}"
MV_OUT="${CLEANMIC_OUTPUT:-BlackHole 2ch}"
MV_BIN_PAT="MetalVoiceCLI --in"
MV_APP_PAT="MetalVoice.app/Contents/MacOS/MetalVoice"
HANDY_LOG="$HOME/Library/Logs/com.pais.handy/handy.log"

# Log lines Handy emits (log_level=debug). If Handy's log level or wording
# changes these must be updated.
START_MARKER="Recording started for binding"
# Handy v0.9.x logs "requested" instead of "started" when a recording begins.
START_MARKER_V09="Recording requested for binding"
STOP_MARKER="Microphone stream stopped"

ts() { date "+%Y-%m-%d %H:%M:%S"; }
mv_running() { pgrep -f "$MV_BIN_PAT" >/dev/null 2>&1; }
start_mv() {
  mv_running && return
  echo "$(ts) starting MetalVoiceCLI ($MV_IN -> $MV_OUT)"
  "$MV_BUNDLE/Contents/MacOS/MetalVoiceCLI" --in "$MV_IN" --out "$MV_OUT" </dev/null >>/tmp/cleanmic-metalvoice.log 2>&1 &
}
stop_mv()  { mv_running && { echo "$(ts) stopping MetalVoiceCLI (idle ${IDLE_SECONDS}s)"; pkill -f "$MV_BIN_PAT"; }; }

# Make sure we start from a clean slate: mic released until the next recording.
# Also quit the old menu-bar app if it is still open from before the switch.
pkill -f "$MV_APP_PAT" 2>/dev/null
stop_mv

# Wait for the log file to exist (Handy may not have created it yet at login).
while [ ! -f "$HANDY_LOG" ]; do sleep 5; done
echo "$(ts) supervisor watching $HANDY_LOG (idle=${IDLE_SECONDS}s)"

recording=0
last_stop=0
# Hard cap: if a stop line is ever missed, don't pin the mic forever.
MAX_SESSION=1800
session_start=0

# Deterministic byte-offset polling instead of `tail -F`. macOS BSD `tail -F`
# proved unreliable at delivering single appended lines through a pipe in the
# launchd context (output buffering / kqueue quirks). Polling the file size and
# reading only the newly-appended bytes each second is simple and dependable.
# 1s latency is irrelevant here: MetalVoice cold-launch already costs ~1-2s, so
# the first utterance after an idle gap warms up regardless.
offset=$(wc -c < "$HANDY_LOG" 2>/dev/null || echo 0)   # start at end: ignore history

while true; do
  sleep 1
  now=$(date +%s)

  size=$(wc -c < "$HANDY_LOG" 2>/dev/null || echo "$offset")
  if [ "$size" -lt "$offset" ]; then
    offset=0          # log was rotated/truncated; re-read from the top
  fi
  if [ "$size" -gt "$offset" ]; then
    # Read only the bytes appended since last poll, line by line.
    while IFS= read -r line; do
      case "$line" in
        *"$START_MARKER"*|*"$START_MARKER_V09"*)
          recording=1
          session_start=$now
          start_mv
          ;;
        *"$STOP_MARKER"*)
          recording=0
          last_stop=$now
          ;;
      esac
    done < <(tail -c "+$((offset + 1))" "$HANDY_LOG" 2>/dev/null)
    offset=$size
  fi

  # Safety: a recording that has run past MAX_SESSION almost certainly missed
  # its stop line; treat it as stopped so the idle timer can reclaim the mic.
  if [ "$recording" -eq 1 ] && [ "$session_start" -ne 0 ] && [ $((now - session_start)) -ge "$MAX_SESSION" ]; then
    recording=0
    last_stop=$now
  fi
  # Release the mic once we've been idle long enough.
  if [ "$recording" -eq 0 ] && [ "$last_stop" -ne 0 ] && [ $((now - last_stop)) -ge "$IDLE_SECONDS" ]; then
    stop_mv
    last_stop=0
  fi
done
