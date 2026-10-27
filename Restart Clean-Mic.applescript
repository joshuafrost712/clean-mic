-- Restart Clean-Mic
-- One-click restart of the clean-mic supervisor (which runs MetalVoice on
-- demand while you dictate). Compiled into "Restart Clean-Mic.app" by setup.sh.

set agentLabel to "com.cleanmic.supervisor"

try
	-- Kill any running MetalVoice instance (so it re-grabs mic / audio devices
	-- fresh next time), then kickstart the supervisor. The supervisor will
	-- relaunch MetalVoice automatically the next time you start a recording.
	do shell script "pkill -f 'MetalVoice.app/Contents/MacOS/MetalVoice' || true; launchctl kickstart -k gui/$(id -u)/" & agentLabel
	display notification "Supervisor restarted. MetalVoice will start when you dictate." with title "Clean-Mic" subtitle "Ready for Handy"
on error errMsg
	try
		-- Agent not loaded? Load it.
		do shell script "launchctl bootstrap gui/$(id -u) " & (quoted form of (POSIX path of (path to home folder))) & "Library/LaunchAgents/" & agentLabel & ".plist"
		display notification "Supervisor was off; started it now." with title "Clean-Mic" subtitle "Ready for Handy"
	on error
		display notification ("Could not restart: " & errMsg) with title "Clean-Mic" subtitle "See ~/Documents/GitHub/clean-mic"
	end try
end try