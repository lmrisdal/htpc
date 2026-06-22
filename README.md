# htpc

Tooling to make a living-room gaming PC behave more like a console: pick up a
controller and the PC wakes, and audio comes back clean afterward.

Two independent pieces that pair well but don't depend on each other:

| Tool | Runs on | What it does |
| --- | --- | --- |
| [`controller-wake`](controller-wake/) | A Linux Bluetooth host (e.g. a small VM) | BLE-scans for a whitelisted game controller and sends a Wake-on-LAN magic packet to wake the PC when the controller powers on. |
| [`htpc-audio-resume`](htpc-audio-resume/) | The Windows HTPC | Cycles the HDMI/DisplayPort audio device on resume from sleep to fix audio crackling. |

## The flow

```
controller powers on
        │  (BLE advertisement)
        ▼
controller-wake  ──  Wake-on-LAN magic packet  ──▶  HTPC wakes from sleep
                                                          │
                                                          ▼
                                                  htpc-audio-resume
                                                  cycles HDMI audio → clean sound
```

## controller-wake

A network-based reimplementation of
[PicoControllerWake](https://github.com/alleras/PicoControllerWake): instead of a
Raspberry Pi Pico emulating a USB keyboard, a ~50-line Python service watches for
a specific controller's Bluetooth advertisement and fires a Wake-on-LAN packet.

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

## Layout

```
htpc/
├── controller-wake/      # Linux: BLE detect → Wake-on-LAN  (Python + systemd)
└── htpc-audio-resume/    # Windows: fix HDMI audio on resume (PowerShell + Task Scheduler)
```
