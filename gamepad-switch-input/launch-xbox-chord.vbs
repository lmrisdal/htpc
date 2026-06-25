' launch-xbox-chord.vbs
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Users\Lars\Documents\htpc\gamepad-switch-input\xbox-chord-trigger.ps1""", 0, False