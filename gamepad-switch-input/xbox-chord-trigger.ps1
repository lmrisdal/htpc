# xbox-chord-trigger.ps1
# Reads Xbox controller via Raw Input (WM_INPUT) using a real WndProc override,
# so it can see input even when Xbox Mode holds the pad via XInput.

Start-Transcript -Path "C:\Users\Lars\Documents\htpc\gamepad-switch-input\chord-debug.log" -Append

$DebugDump = $false   # set $false after identifying button offsets

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class RawGamepadWindow : NativeWindow {
    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICE {
        public ushort usUsagePage;
        public ushort usUsage;
        public uint dwFlags;
        public IntPtr hwndTarget;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTHEADER {
        public uint dwType;
        public uint dwSize;
        public IntPtr hDevice;
        public IntPtr wParam;
    }

    [DllImport("user32.dll")]
    static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] d, uint num, uint size);
    [DllImport("user32.dll")]
    static extern uint GetRawInputData(IntPtr h, uint cmd, IntPtr data, ref uint size, uint hdrSize);

    const int WM_INPUT = 0x00FF;
    const uint RID_INPUT = 0x10000003;
    const uint RIM_TYPEHID = 2;
    const uint RIDEV_INPUTSINK = 0x00000100;

    public Action<byte[]> OnReport;

    public RawGamepadWindow() {
        CreateParams cp = new CreateParams();
        cp.Caption = "RawGamepadHidden";
        cp.Parent = (IntPtr)(-3); // HWND_MESSAGE
        this.CreateHandle(cp);

        RAWINPUTDEVICE[] rid = new RAWINPUTDEVICE[2];
        rid[0].usUsagePage = 0x01; rid[0].usUsage = 0x05; // gamepad
        rid[0].dwFlags = RIDEV_INPUTSINK; rid[0].hwndTarget = this.Handle;
        rid[1].usUsagePage = 0x01; rid[1].usUsage = 0x04; // joystick
        rid[1].dwFlags = RIDEV_INPUTSINK; rid[1].hwndTarget = this.Handle;
        RegisterRawInputDevices(rid, 2, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)));
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_INPUT) {
            uint size = 0;
            uint hdr = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER));
            GetRawInputData(m.LParam, RID_INPUT, IntPtr.Zero, ref size, hdr);
            if (size > 0) {
                IntPtr buf = Marshal.AllocHGlobal((int)size);
                try {
                    if (GetRawInputData(m.LParam, RID_INPUT, buf, ref size, hdr) > 0) {
                        uint dwType = (uint)Marshal.ReadInt32(buf, 0);
                        if (dwType == RIM_TYPEHID) {
                            int sizeHid = Marshal.ReadInt32(buf, (int)hdr);
                            int count   = Marshal.ReadInt32(buf, (int)hdr + 4);
                            int dataOff = (int)hdr + 8;
                            int total = sizeHid * count;
                            byte[] report = new byte[total];
                            Marshal.Copy(IntPtr.Add(buf, dataOff), report, 0, total);
                            if (OnReport != null) OnReport(report);
                        }
                    }
                } finally {
                    Marshal.FreeHGlobal(buf);
                }
            }
        }
        base.WndProc(ref m);
    }
}
'@

Add-Type -AssemblyName System.Windows.Forms

# --- Button offsets: FILL IN from debug dump ---
$BTN_L3 = @{ Byte = 12; Bit = 0 }
$BTN_RB = @{ Byte = 11; Bit = 5 }
$BTN_X  = @{ Byte = 11; Bit = 2 }
$comboHeld = $false

# Bytes to ignore in debug diff (analog sticks/triggers that stream constantly).
# Leave empty at first; add noisy byte indices here once you see which ones jitter.
$IgnoreBytes = @()

function Test-Bit($bytes, $def) {
    if ($def.Byte -ge $bytes.Length) { return $false }
    return (($bytes[$def.Byte] -shr $def.Bit) -band 1) -eq 1
}

$script:baseline = $null

$win = New-Object RawGamepadWindow
$win.OnReport = {
    param($report)
    if ($DebugDump) {
        if ($null -eq $script:baseline) {
            $script:baseline = $report.Clone()
            Write-Host "Baseline captured ($($report.Length) bytes). Set controller down, let sticks settle, then press buttons one at a time."
            return
        }
        $diffs = @()
        for ($i = 0; $i -lt $report.Length; $i++) {
            if ($IgnoreBytes -contains $i) { continue }
            if ($report[$i] -ne $script:baseline[$i]) {
                $diffs += "byte[$i]: $($script:baseline[$i].ToString('X2')) -> $($report[$i].ToString('X2'))"
            }
        }
        if ($diffs.Count -gt 0) {
            Write-Host ($diffs -join '  |  ')
        }
    } else {
        $l3 = Test-Bit $report $BTN_L3
        $rb = Test-Bit $report $BTN_RB
        $x  = Test-Bit $report $BTN_X
        if ($l3 -and $rb -and $x) {
            if (-not $script:comboHeld) {
                $script:comboHeld = $true
                Start-Process -FilePath "C:\Program Files\LGTV Companion\LGTV Companion.exe" `
                    -ArgumentList '-screenon','Device1','-set_input_type','HDMI_4','pc','PC','Device1','-sethdmi','4','Device1' `
                    -WindowStyle Hidden
            }
        } else {
            $script:comboHeld = $false
        }
    }
}.GetNewClosure()

if ($DebugDump) {
    Write-Host "DEBUG MODE: baseline-diff. Press L3, then RB, then X individually."
    Write-Host "The byte that flips cleanly on press and reverts on release is a button byte.`n"
}

[System.Windows.Forms.Application]::Run()