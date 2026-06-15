-- Restart Clean-Mic
-- One-click restart of the MetalVoice denoiser (clean-mic pipeline).
-- Compiled into "Restart Clean-Mic.app" by setup.sh / build step.

set agentLabel to "com.cleanmic.metalvoice"

try
	-- Kill the MetalVoice app itself (so it re-grabs the mic / audio devices),
	-- then kickstart the agent's wrapper, which relaunches a fresh instance.
	-- (kickstart alone won't restart an already-running app, since `open -a`
	-- just re-activates it.)
	do shell script "pkill -f 'MetalVoice.app/Contents/MacOS/MetalVoice' || true; launchctl kickstart -k gui/$(id -u)/" & agentLabel
	display notification "Denoiser restarted. Give it ~3 seconds, then dictate." with title "Clean-Mic" subtitle "VoiceInk is good to go"
on error errMsg
	try
		-- Agent not loaded? Load it, which also launches MetalVoice.
		do shell script "launchctl bootstrap gui/$(id -u) " & (quoted form of (POSIX path of (path to home folder))) & "Library/LaunchAgents/" & agentLabel & ".plist"
		display notification "Denoiser was off; started it now." with title "Clean-Mic" subtitle "VoiceInk is good to go"
	on error
		display notification ("Could not restart: " & errMsg) with title "Clean-Mic" subtitle "See ~/Documents/GitHub/clean-mic"
	end try
end try