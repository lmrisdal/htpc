# restart-hdmi-audio.ps1
# Cycles the HDMI/DisplayPort audio device to clear crackling after resume.
# Must run elevated (the scheduled task runs it as SYSTEM).
#
# Hardening: the PnP-level Disable/Enable cycle re-initializes the HDMI audio
# link (which is what actually clears the crackle), but if Enable fails after
# Disable succeeds the device is left torn down and invisible to the Sound
# panel. This script guarantees the device is never left disabled:
#   * retries Enable several times (the "Generic failure" right after Disable
#     is usually a transient "device busy")
#   * verifies the final PnP state and force-enables again if still disabled
#   * self-heals on startup: re-enables any matching device that is already
#     sitting disabled from a previous failed run

# --- CONFIG ---------------------------------------------------------------
# Substring(s) matching your HDMI/DP audio device's FriendlyName.
# Find yours with:
#   Get-PnpDevice -Class MEDIA | Format-Table FriendlyName, Status, InstanceId -AutoSize
# Typical names: "NVIDIA High Definition Audio", "AMD High Definition Audio".
$NamePatterns = @(
    'NVIDIA High Definition Audio'
    'AMD High Definition Audio'
)

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
$log = Join-Path $logDir 'resume-audio.log'

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
    Write-Log "  -> FAILED to re-enable '$friendlyName' after $EnableRetries attempts. Device may be left DISABLED."
    return $false
}

Start-Sleep -Seconds $SettleSeconds

# Match by name. Do NOT filter on Status -eq 'OK' here: a device left disabled
# by a previous failed run reports Status 'Error', and we want to heal those.
$devices = Get-PnpDevice -Class MEDIA |
    Where-Object {
        $dev = $_
        $NamePatterns | Where-Object { $dev.FriendlyName -like "*$_*" }
    }

if (-not $devices) {
    Write-Log "No matching HDMI audio device found (patterns: $($NamePatterns -join ', '))."
    exit 1
}

foreach ($d in $devices) {
    try {
        # Self-heal: if it is already disabled from a prior failed run, just
        # bring it back up. No need to cycle a device that is already down.
        if ($d.Problem -eq 'CM_PROB_DISABLED') {
            Write-Log "Found '$($d.FriendlyName)' already DISABLED [$($d.InstanceId)] - re-enabling"
            [void](Invoke-EnableWithRetry $d.InstanceId $d.FriendlyName)
            continue
        }

        Write-Log "Cycling '$($d.FriendlyName)' [$($d.InstanceId)]"
        Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false
        Start-Sleep -Seconds $CycleGapSeconds
        [void](Invoke-EnableWithRetry $d.InstanceId $d.FriendlyName)
    } catch {
        Write-Log "  -> ERROR: $($_.Exception.Message)"
        # Whatever went wrong, never leave the device disabled.
        if (-not (Test-DeviceEnabled $d.InstanceId)) {
            Write-Log "  -> device not enabled after error; attempting recovery"
            [void](Invoke-EnableWithRetry $d.InstanceId $d.FriendlyName)
        }
    }
}
