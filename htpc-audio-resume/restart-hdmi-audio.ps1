# restart-hdmi-audio.ps1
# Cycles the HDMI/DisplayPort audio device to clear crackling after resume.
# Must run elevated (the scheduled task runs it as SYSTEM).

# --- CONFIG ---------------------------------------------------------------
# Substring(s) matching your HDMI/DP audio device's FriendlyName.
# Find yours with:
#   Get-PnpDevice -Class MEDIA | Where-Object Status -eq 'OK' |
#       Format-Table FriendlyName, InstanceId -AutoSize
# Typical names: "NVIDIA High Definition Audio", "AMD High Definition Audio".
$NamePatterns = @(
    'NVIDIA High Definition Audio'
    'AMD High Definition Audio'
)

# Seconds to wait after resume before cycling (let devices settle first).
$SettleSeconds = 5
# --------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$logDir = Join-Path $env:ProgramData 'htpc-audio-resume'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'resume-audio.log'

function Write-Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Tee-Object -FilePath $log -Append
}

Start-Sleep -Seconds $SettleSeconds

$devices = Get-PnpDevice -Class MEDIA | Where-Object { $_.Status -eq 'OK' } |
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
        Write-Log "Cycling '$($d.FriendlyName)' [$($d.InstanceId)]"
        Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false
        Start-Sleep -Seconds 2
        Enable-PnpDevice  -InstanceId $d.InstanceId -Confirm:$false
        Write-Log "  -> re-enabled OK"
    } catch {
        Write-Log "  -> ERROR: $($_.Exception.Message)"
    }
}
