#!/usr/bin/env python3
"""
controller-wake: BLE-scan for a whitelisted game controller and send a
Wake-on-LAN magic packet to a target PC when the controller powers on.

Replaces the Pico + USB-HID approach from PicoControllerWake with a
network-based wake, intended to run in a Bluetooth-host VM (USB dongle
passed through) on Proxmox.

Dependency:  pip install bleak
"""

import asyncio
import logging
import socket
import time

from bleak import BleakScanner

# ---------------------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------------------

# BLE MAC addresses allowed to wake the PC (uppercase, colon-separated).
# Fill this in once you've identified your controller. You can add several.
WHITELIST = {
    # "AA:BB:CC:DD:EE:FF",
}

# Target PC's NIC MAC address (the machine you want to wake).
TARGET_MAC = "11:22:33:44:55:66"

# Broadcast address to send the magic packet to.
# 255.255.255.255 is the safe default: it goes out as an Ethernet broadcast
# (dest MAC ff:ff:ff:ff:ff:ff), which floods every port of an unmanaged switch
# and reaches the target at layer 2 even if it's on a different IP VLAN. Use a
# subnet broadcast (e.g. 192.168.1.255) only if you specifically need to scope it.
BROADCAST_IP = "255.255.255.255"
WOL_PORT = 9  # 7 or 9 are the conventional WoL ports

# Don't fire again within this many seconds of a successful wake.
COOLDOWN_SECONDS = 60

# Set True to log EVERY advert seen (useful for finding your controller's MAC).
# Set False once your whitelist is set, to keep logs quiet.
LOG_UNKNOWN = True

# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("controller-wake")

_last_wake = 0.0


def send_magic_packet(mac: str) -> None:
    """Build and broadcast a Wake-on-LAN magic packet for `mac`."""
    clean = mac.replace(":", "").replace("-", "")
    if len(clean) != 12:
        raise ValueError(f"Invalid MAC address: {mac}")

    payload = bytes.fromhex("FF" * 6 + clean * 16)

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        s.sendto(payload, (BROADCAST_IP, WOL_PORT))

    log.info("Sent WoL magic packet to %s via %s:%d", mac, BROADCAST_IP, WOL_PORT)


def detection_callback(device, advertisement_data) -> None:
    global _last_wake

    addr = (device.address or "").upper()

    if addr in WHITELIST:
        now = time.monotonic()
        if now - _last_wake < COOLDOWN_SECONDS:
            return  # still cooling down; ignore
        log.info(
            "Whitelisted controller detected: %s (%s, rssi=%s)",
            addr, device.name, advertisement_data.rssi,
        )
        try:
            send_magic_packet(TARGET_MAC)
            _last_wake = now
        except Exception as exc:  # noqa: BLE001
            log.error("Failed to send WoL packet: %s", exc)
    elif LOG_UNKNOWN:
        log.info(
            "Unknown advert: %s name=%r rssi=%s",
            addr, device.name, advertisement_data.rssi,
        )


async def main() -> None:
    log.info("Starting BLE scan. Whitelist: %s", WHITELIST or "(empty)")
    scanner = BleakScanner(detection_callback)
    await scanner.start()
    try:
        while True:
            await asyncio.sleep(3600)
    finally:
        await scanner.stop()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Stopped.")
