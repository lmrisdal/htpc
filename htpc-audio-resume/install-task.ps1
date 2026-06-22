# install-task.ps1
# Registers a scheduled task that runs restart-hdmi-audio.ps1 on resume from sleep.
# Run this ONCE, from an elevated PowerShell (Run as Administrator).

$ErrorActionPreference = 'Stop'

# Where the worker script lives. Adjust if you put it elsewhere.
$scriptPath = "$env:USERPROFILE\Documents\htpc\htpc-audio-resume\restart-hdmi-audio.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "Script not found at $scriptPath - copy restart-hdmi-audio.ps1 there first (or edit this path)."
}

$taskName = 'Restart HDMI Audio On Resume'

# Trigger: System log, Power-Troubleshooter, Event ID 1 = wake from sleep.
$query = @"
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and (EventID=1)]]</Select>
  </Query>
</QueryList>
"@

$class = Get-CimClass `
    -Namespace ROOT\Microsoft\Windows\TaskScheduler `
    -ClassName MSFT_TaskEventTrigger
$trigger = New-CimInstance -CimClass $class -ClientOnly
$trigger.Enabled      = $true
$trigger.Subscription = $query

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

$principal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $taskName `
    -Trigger $trigger `
    -Action $action `
    -Principal $principal `
    -Settings $settings `
    -Force

Write-Host "Registered scheduled task '$taskName'."
Write-Host "It will run on the next resume from sleep. Log: %ProgramData%\htpc-audio-resume\resume-audio.log"
