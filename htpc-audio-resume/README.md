# htpc-audio-resume

Fixes HDMI/DisplayPort audio **crackling after resume from sleep** on Windows by
cycling (disable → enable) the GPU's HDMI audio device whenever the PC wakes.

## How it works

A scheduled task listens for the Windows resume event (System log,
`Microsoft-Windows-Power-Troubleshooter`, Event ID 1 — fired on wake from sleep)
and runs a PowerShell script as SYSTEM that disables and re-enables the HDMI
audio device, forcing the driver to reinitialize cleanly.

## Install

1. **Find your HDMI audio device name.** In any PowerShell window:
   ```powershell
   Get-PnpDevice -Class MEDIA | Where-Object Status -eq 'OK' |
       Format-Table FriendlyName, InstanceId -AutoSize
   ```
   Note the HDMI/DP one — e.g. `NVIDIA High Definition Audio` or
   `AMD High Definition Audio`. If it differs, edit `$NamePatterns` at the top of
   `restart-hdmi-audio.ps1`.

2. **Copy the scripts** to `C:\Scripts\htpc-audio-resume\` (or edit `$scriptPath`
   in `install-task.ps1` to wherever you put them).

3. **Register the task** — open PowerShell **as Administrator** and run:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass -Force
   C:\Scripts\htpc-audio-resume\install-task.ps1
   ```

## Test

You don't have to wait for a real sleep cycle — run the worker manually from an
elevated PowerShell to confirm it finds and cycles the device:
```powershell
C:\Scripts\htpc-audio-resume\restart-hdmi-audio.ps1
```
Your HDMI audio should briefly drop and come back. Then do a real
sleep → wake to confirm the task fires automatically.

Logs: `%ProgramData%\htpc-audio-resume\resume-audio.log`

## Tuning

- `$SettleSeconds` (default 5): increase if the device isn't fully back when the
  script runs right after resume.
- `$NamePatterns`: add/adjust to match exactly your device(s). Be specific enough
  not to also match onboard Realtek audio, unless you want that cycled too.

## Notes

- A running game's audio will glitch for ~1–2 seconds while the device cycles,
  then recover clean — that's expected and far better than persistent crackle.
- If cycling the device isn't enough, a heavier hammer is restarting the audio
  services (`Restart-Service Audiosrv -Force`), but the device cycle is usually
  the right fix for HDMI-specific crackle.
- This is independent of the controller-wake setup; it just reacts to the same
  resume event on the PC side.
