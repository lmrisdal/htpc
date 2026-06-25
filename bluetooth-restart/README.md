# bluetooth-restart

Fixes Bluetooth devices (controllers, headsets, keyboards) **not reconnecting
after resume from sleep** on Windows by cycling the Bluetooth radio at the PnP
level whenever the PC wakes.

## How it works

A scheduled task listens for the Windows resume event (System log,
`Microsoft-Windows-Power-Troubleshooter`, Event ID 1) and runs
`restart-bluetooth.ps1` as SYSTEM. The script:

1. Waits a short settle period for the system to stabilize.
2. Finds the physical Bluetooth radio by bus path (`USB\` or `PCI\`) — this
   avoids accidentally cycling the BT enumerators or paired-device nodes that
   hang off the radio.
3. Disables the radio, waits briefly, then re-enables it with retries and
   back-off (a "Generic failure" right after disable is usually transient).
4. Self-heals on startup: if the radio is already sitting disabled from a
   previous failed run, it just re-enables without cycling.

## Install

There is no installer script yet — register the task manually.

1. **Find your Bluetooth radio's Instance ID:**
   ```powershell
   Get-PnpDevice -Class Bluetooth | Format-Table FriendlyName, Status, InstanceId -AutoSize
   ```
   Look for the entry whose `InstanceId` starts with `USB\` or `PCI\` — that is
   the physical radio. The script auto-selects it via `$RadioBusPattern`; you
   only need to check if the default pattern doesn't match.

2. **Copy** `restart-bluetooth.ps1` somewhere permanent, e.g.
   `C:\Scripts\htpc-audio-resume\`.

3. **Register the scheduled task** — open PowerShell **as Administrator**:
   ```powershell
   $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
                  -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Scripts\htpc-audio-resume\restart-bluetooth.ps1"'
   $trigger = New-ScheduledTaskTrigger -AtStartup   # placeholder; event trigger added below
   $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
   $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest

   Register-ScheduledTask -TaskName 'HTPC Bluetooth Resume' `
       -Action $action -Settings $settings -Principal $principal

   # Replace the startup trigger with a wake-event trigger
   $task = Get-ScheduledTask -TaskName 'HTPC Bluetooth Resume'
   $eventTrigger = Get-Content -Raw - << 'XML'
   <QueryList>
     <Query Id="0" Path="System">
       <Select Path="System">
         *[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]
       </Select>
     </Query>
   </QueryList>
   XML
   # (Easiest to set the event trigger via Task Scheduler GUI: Triggers → New →
   #  On an event → Log: System, Source: Power-Troubleshooter, Event ID: 1)
   ```

   **Tip:** the quickest path is to open Task Scheduler, duplicate the
   `HTPC Audio Resume` task (from `htpc-audio-resume`), rename it, and swap the
   action to point at `restart-bluetooth.ps1`. The event trigger is identical.

## Test

Run the script directly from an elevated PowerShell — Bluetooth should drop and
reconnect within a few seconds:
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Scripts\htpc-audio-resume\restart-bluetooth.ps1"
```
Then do a real sleep → wake to confirm the task fires automatically.

Logs: `%ProgramData%\htpc-audio-resume\resume-bluetooth.log`

## Tuning

| Variable | Default | Effect |
|---|---|---|
| `$RadioBusPattern` | `'^(USB\|PCI)\\'` | Selects the physical radio by bus. Change if your adapter appears on a different bus. |
| `$SettleSeconds` | `5` | Wait after resume before cycling. Increase if the script runs before Bluetooth is ready. |
| `$CycleGapSeconds` | `2` | Pause between Disable and Enable. |
| `$EnableRetries` | `5` | How many times to retry Enable before giving up. |
| `$EnableRetryGapSeconds` | `2` | Back-off between Enable attempts. |

## Notes

- Cycling at the radio level re-initializes the entire Bluetooth stack — LE
  services, RFCOMM, and all paired devices reconnect as if the adapter was just
  plugged in.
- If you have both a USB and a PCI Bluetooth device, the script will cycle both.
  Narrow `$RadioBusPattern` (e.g. `'^USB\\'`) to target only one.
- The script never leaves the radio disabled: if Enable fails after all retries,
  it logs an error but attempts one final recovery pass.
