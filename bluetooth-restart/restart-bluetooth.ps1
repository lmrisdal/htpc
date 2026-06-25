# restart-bluetooth.ps1
# Cycles the Bluetooth radio adapter to recover it after resume from sleep.
# Must run elevated (the scheduled task runs it as SYSTEM).
#
# Cycling the radio at the PnP level re-initializes the whole Bluetooth stack
# (LE services, RFCOMM, paired devices all hang off the radio). Same hardening
# as restart-hdmi-audio.ps1: the radio is never left disabled if Enable fails.
#   * retries Enable several times (a "Generic failure" right after Disable is
#     usually a transient "device busy")
#   * verifies the final PnP state and force-enables again if still disabled
#   * self-heals on startup: re-enables a radio already sitting disabled from a
#     previous failed run

# --- CONFIG ---------------------------------------------------------------
# The Bluetooth radio is selected by bus rather than vendor name, so this keeps
# working if you swap adapters. The radio sits on USB or PCI; the other class
# Bluetooth entries (BTH\, BTHLE\, BTHLEDEVICE\) are enumerators / paired
# devices that hang off it and must NOT be cycled directly.
# Inspect yours with:
#   Get-PnpDevice -Class Bluetooth | Format-Table FriendlyName, Status, InstanceId -AutoSize
$RadioBusPattern = '^(USB|PCI)\\'

# Seconds to wait after resume before cycling (let devices settle first).
$SettleSeconds = 5
# Seconds between Disable and Enable.
$CycleGapSeconds = 2
# How many times to attempt Enable before giving up, and the back-off between.
$EnableRetries = 5
$EnableRetryGapSeconds = 2
# --------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$logDir = Join-Path $env:ProgramData 'htpc-audio-resume'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'resume-bluetooth.log'

function Write-Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Tee-Object -FilePath $log -Append
}

# Returns $true once the device is reported enabled (not CM_PROB_DISABLED).
function Test-DeviceEnabled($instanceId) {
    $d = Get-PnpDevice -InstanceId $instanceId -ErrorAction SilentlyContinue
    return ($d -and $d.Problem -ne 'CM_PROB_DISABLED')
}

# Enable with retries. Returns $true if the device ends up enabled.
function Invoke-EnableWithRetry($instanceId, $friendlyName) {
    for ($i = 1; $i -le $EnableRetries; $i++) {
        try {
            Enable-PnpDevice -InstanceId $instanceId -Confirm:$false
        } catch {
            Write-Log "  -> Enable attempt $i/$EnableRetries failed: $($_.Exception.Message)"
        }
        if (Test-DeviceEnabled $instanceId) {
            Write-Log "  -> enabled OK (attempt $i)"
            return $true
        }
        Start-Sleep -Seconds $EnableRetryGapSeconds
    }
    # Final check in case the last Enable just needed a moment to settle.
    if (Test-DeviceEnabled $instanceId) {
        Write-Log "  -> enabled OK (after retries)"
        return $true
    }
    Write-Log "  -> FAILED to re-enable '$friendlyName' after $EnableRetries attempts. Radio may be left DISABLED."
    return $false
}

Start-Sleep -Seconds $SettleSeconds

# Select the physical radio(s). Do NOT filter on Status -eq 'OK' here: a radio
# left disabled by a previous failed run reports Status 'Error', and we want to
# heal those.
$radios = Get-PnpDevice -Class Bluetooth |
    Where-Object { $_.InstanceId -match $RadioBusPattern }

if (-not $radios) {
    Write-Log "No Bluetooth radio found on USB/PCI (pattern: $RadioBusPattern)."
    exit 1
}

foreach ($r in $radios) {
    try {
        # Self-heal: if it is already disabled from a prior failed run, just
        # bring it back up. No need to cycle a radio that is already down.
        if ($r.Problem -eq 'CM_PROB_DISABLED') {
            Write-Log "Found '$($r.FriendlyName)' already DISABLED [$($r.InstanceId)] - re-enabling"
            [void](Invoke-EnableWithRetry $r.InstanceId $r.FriendlyName)
            continue
        }

        Write-Log "Cycling '$($r.FriendlyName)' [$($r.InstanceId)]"
        Disable-PnpDevice -InstanceId $r.InstanceId -Confirm:$false
        Start-Sleep -Seconds $CycleGapSeconds
        [void](Invoke-EnableWithRetry $r.InstanceId $r.FriendlyName)
    } catch {
        Write-Log "  -> ERROR: $($_.Exception.Message)"
        # Whatever went wrong, never leave the radio disabled.
        if (-not (Test-DeviceEnabled $r.InstanceId)) {
            Write-Log "  -> radio not enabled after error; attempting recovery"
            [void](Invoke-EnableWithRetry $r.InstanceId $r.FriendlyName)
        }
    }
}
