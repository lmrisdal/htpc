# controller-wake

Wake a PC when a specific Bluetooth game controller powers on.

A network-based reimplementation of
[PicoControllerWake](https://github.com/alleras/PicoControllerWake): instead of
a Raspberry Pi Pico emulating a USB keyboard, a small Python service BLE-scans
for a whitelisted controller and sends a **Wake-on-LAN** magic packet to the
target PC.

```
controller powers on → BLE advert seen → MAC matches whitelist → WoL magic packet → PC wakes
```

## Intended setup

A small **Bluetooth-host VM** on Proxmox with a USB BT dongle passed through.
A VM (rather than an LXC) gives a clean, exclusive hardware boundary and avoids
the namespaced-capability problems that block Bluetooth in unprivileged
containers.

## Prerequisites

- **Target PC:** Wake-on-LAN enabled in BIOS, and on the NIC.
  - Linux: `ethtool -s <iface> wol g` (persist via your network config)
  - Windows: enable "Wake on Magic Packet" + "Allow this device to wake the
    computer" on the network adapter.
- **VM:** USB BT dongle passed through, BlueZ running.
- The VM and target PC must share a broadcast domain (same VLAN/subnet is
  easiest).

## Install (Debian/Ubuntu VM — systemd)

```sh
sudo apt update
sudo apt install -y bluez python3-venv

sudo mkdir -p /opt/controller-wake
sudo cp controller_wake.py /opt/controller-wake/
sudo python3 -m venv /opt/controller-wake/venv
sudo /opt/controller-wake/venv/bin/pip install bleak

# Confirm Bluetooth works first:
bluetoothctl   # then: scan le  (power your controller on, watch for its MAC)

# Service
sudo cp controller-wake.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now controller-wake
journalctl -u controller-wake -f
```

## Configuration

Edit the CONFIG block at the top of `controller_wake.py`:

1. **Find your controller's MAC.** Leave `WHITELIST` empty, keep
   `LOG_UNKNOWN = True`, run the service, and power your controller on/off a few
   times. The address that reliably appears only when the controller turns on is
   the one you want.
2. **Lock it down.** Put that MAC in `WHITELIST`, set `TARGET_MAC` to the PC's
   NIC MAC, leave `BROADCAST_IP` at `255.255.255.255` (see note below), and set
   `LOG_UNKNOWN = False`. Restart the service.

| Setting            | Meaning                                                     |
| ------------------ | ----------------------------------------------------------- |
| `WHITELIST`        | BLE MACs allowed to trigger a wake                          |
| `TARGET_MAC`       | NIC MAC of the PC to wake                                   |
| `BROADCAST_IP`     | Where to send the magic packet (`255.255.255.255` default)  |
| `WOL_PORT`         | 7 or 9 (conventional)                                       |
| `COOLDOWN_SECONDS` | Suppress repeat wakes within this window                    |
| `LOG_UNKNOWN`      | Log all adverts (for discovery) vs. stay quiet              |

## Notes

- **MAC randomization:** most game controllers (Xbox, DualSense, 8BitDo)
  advertise with a stable public MAC, so plain MAC filtering works. If yours
  rotates its address, you'll need IRK-based resolution (bond the controller so
  BlueZ stores its Identity Resolving Key).
- **Adding more BT jobs later:** multiple client apps under one `bluetoothd` is
  fine. The one shared resource to coordinate is BLE _scanning_ — if you add a
  second scanner, have them cooperate rather than starting/stopping scans
  independently.
- **WoL across VLANs:** if the wake host and the PC are on different IP subnets
  but share an unmanaged switch, keep `BROADCAST_IP = "255.255.255.255"`. The
  magic packet floods the switch as a layer-2 broadcast and reaches the PC's NIC
  regardless of subnet, bypassing the router and its inter-VLAN firewall. Unicast
  to the PC's IP would instead require routing + a static ARP entry for the
  sleeping host — avoid it unless your switch enforces real VLAN isolation.
