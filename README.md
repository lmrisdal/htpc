# htpc

Tooling to make a living-room gaming PC behave more like a console: pick up a
controller and the PC wakes, and audio comes back clean afterward.

Independent pieces that pair well but don't depend on each other:

| Tool | Runs on | What it does |
| --- | --- | --- |
| [`controller-wake`](controller-wake/) | A Linux Bluetooth host (e.g. a small VM) | BLE-scans for a whitelisted game controller and sends a Wake-on-LAN magic packet to wake the PC when the controller powers on. |
| [`htpc-audio-resume`](htpc-audio-resume/) | The Windows HTPC | Cycles the HDMI/DisplayPort audio device on resume from sleep to fix audio crackling. |
| [`bluetooth-restart`](bluetooth-restart/) | The Windows HTPC | Cycles the Bluetooth radio on resume from sleep to recover paired devices (controllers, headsets). |
| [`gamepad-switch-input`](gamepad-switch-input/) | The Windows HTPC | Chord shortcut (L3 + RB + X) on an Xbox controller that switches the TV to the HTPC's HDMI input via LGTV Companion. |

## controller-wake

A Python service watches for a specific controller's Bluetooth advertisement and fires a Wake-on-LAN packet.

- Runs anywhere with a Bluetooth adapter and BlueZ — designed for a small
  dedicated VM with a USB BT dongle passed through (Proxmox).
- Whitelists by BLE MAC, so only *your* controller wakes the PC.
- Uses an Ethernet-broadcast (`255.255.255.255`) magic packet, which reaches the
  PC at layer 2 even across IP VLANs on a shared switch.

Setup and configuration: [controller-wake/README.md](controller-wake/README.md).

## htpc-audio-resume

Fixes HDMI/DP audio crackling after the PC wakes from sleep. A scheduled task
listens for the Windows resume event and runs a PowerShell script that disables
and re-enables the GPU's HDMI audio device, forcing a clean driver reinit.

Setup: [htpc-audio-resume/README.md](htpc-audio-resume/README.md).

## bluetooth-restart

Fixes Bluetooth devices (controllers, headsets) not reconnecting after the PC
wakes from sleep by cycling the Bluetooth radio at the PnP level. Same
scheduled-task pattern as `htpc-audio-resume`.

Setup: [bluetooth-restart/README.md](bluetooth-restart/README.md).

## gamepad-switch-input

Watches for a button chord (L3 + RB + X) on an Xbox controller and fires
[LGTV Companion](https://github.com/JPersson77/LGTVCompanion) to switch the TV
to the HTPC's HDMI input. Reads via Raw Input (WM_INPUT) so it works even while
Xbox Mode has the pad via XInput.

Setup: [gamepad-switch-input/README.md](gamepad-switch-input/README.md).

## Layout

```
htpc/
├── controller-wake/      # Linux: BLE detect → Wake-on-LAN  (Python + systemd)
├── htpc-audio-resume/    # Windows: fix HDMI audio on resume (PowerShell + Task Scheduler)
├── bluetooth-restart/    # Windows: cycle BT radio on resume (PowerShell + Task Scheduler)
└── gamepad-switch-input/ # Windows: chord shortcut → switch TV input (PowerShell + VBScript)
```
