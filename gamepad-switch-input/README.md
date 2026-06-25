# gamepad-switch-input

Press **L3 + RB + X** on an Xbox controller to switch the TV to the HTPC's
HDMI input via [LGTV Companion](https://github.com/JPersson77/LGTVCompanion).
Useful when the TV woke to a different source and you want to switch back
without touching a remote.

## How it works

`xbox-chord-trigger.ps1` registers for Raw Input (`WM_INPUT`) on a hidden
message-only window. This bypasses the normal focus requirement and also works
while Xbox Game Bar / Xbox Mode holds the controller via XInput. On every HID
report it checks three bits:

| Button | Byte | Bit |
|---|---|---|
| L3 (left stick click) | 12 | 0 |
| RB (right bumper) | 11 | 5 |
| X | 11 | 2 |

When all three are held simultaneously it fires LGTV Companion with arguments
that switch `Device1` to HDMI input 4 in PC mode. The chord is edge-triggered
(fires once on press, not repeatedly while held).

`launch-xbox-chord.vbs` is a tiny wrapper that starts the PowerShell script
completely hidden (no console window, no taskbar icon).

## Prerequisites

- [LGTV Companion](https://github.com/JPersson77/LGTVCompanion) installed to
  `C:\Program Files\LGTV Companion\` with your TV already configured as
  `Device1`.
- An Xbox controller connected (wired or wireless via the Xbox adapter).

## Install

1. **Verify button offsets** (skip if your controller matches the table above):
   Set `$DebugDump = $true` near the top of `xbox-chord-trigger.ps1`, run the
   script in a normal PowerShell window, and press L3, RB, X one at a time.
   The script prints which byte/bit flips for each press. Fill in `$BTN_L3`,
   `$BTN_RB`, `$BTN_X`, then set `$DebugDump = $false`.

2. **Edit the LGTV Companion arguments** in `xbox-chord-trigger.ps1` if your
   TV device name or HDMI port differs:
   ```powershell
   -ArgumentList '-screenon','Device1','-set_input_type','HDMI_4','pc','PC','Device1','-sethdmi','4','Device1'
   ```

3. **Run at startup via Task Scheduler** — open Task Scheduler as Administrator:
   - **General:** run only when user is logged on, do NOT run with highest
     privileges (doesn't need elevation).
   - **Trigger:** At log on (for your user).
   - **Action:** Start a program → `wscript.exe` →
     Arguments: `"C:\Users\Lars\Documents\htpc\gamepad-switch-input\launch-xbox-chord.vbs"`
   - **Conditions:** uncheck "Start only if on AC power".
   - **Settings:** uncheck "Stop the task if it runs longer than…"

   The VBScript launcher keeps the window hidden so nothing appears on screen.

## Customizing the chord

Open `xbox-chord-trigger.ps1` and change the three `$BTN_*` variables and the
`if ($l3 -and $rb -and $x)` check to whatever combination you prefer. You can
use any button exposed in the raw HID report.

## Debug mode

Set `$DebugDump = $true` and run the script interactively. It captures a
baseline on the first report, then prints byte-level diffs as you press buttons.
Add any bytes that jitter constantly (analog sticks, triggers) to `$IgnoreBytes`
to filter noise:
```powershell
$IgnoreBytes = @(0, 1, 2, 3)   # example: first four bytes are stick axes
```

Logs (transcript): `gamepad-switch-input\chord-debug.log`
