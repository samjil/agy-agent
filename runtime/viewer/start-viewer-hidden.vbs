' start-viewer-hidden.vbs
' Double-click (or put a shortcut in the Startup folder) to start the samjil viewer and the agy watcher
' in the background: no console window and no browser tab. Open http://127.0.0.1:8787 yourself when you want to look.
' wscript.exe is a GUI program, so nothing flashes on screen. Nothing happens if the viewer is already running.
' To stop them: run  ensure-viewer-running.ps1 -Stop  (viewer) and  stop-agy.ps1  (watcher).
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File """ & dir & "\ensure-viewer-running.ps1""", 0, False
