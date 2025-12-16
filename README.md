# AmpSwitch
Universal amplifier power control for Volumio, Moode & MPD

AmpSwitch is a lightweight, hardware-safe daemon that automatically powers your audio amplifier only when music is playing.

It monitors the playback state of popular Linux audio players and controls one or more GPIO-connected relays to emulate an amplifier’s power button or enable line — with proper delays, sequencing, and startup safety.

Designed for real Hi-Fi setups, not just hobby demos.

---

## Features

- Auto-detects audio player
  - Volumio (REST API)
  - MPD (Moode, RuneAudio, plain MPD)

- Relay control modes
  - Toggle mode – pulse relay to emulate power button (ON / OFF)
  - Hold mode – relay stays ON while music plays

- Smart stop delay
  - Prevents relay chatter during track changes, Spotify gaps, radio buffering

- Multi-relay sequencing (optional)
  - Power devices in order (DAC → preamp → power amp)
  - Reverse order on shutdown

- Startup safe
  - No relay action on boot
  - Optional Force OFF only when running as a background service

- Interactive test mode
  - Test behavior safely before installing as a service

- Clean uninstall
  - Available only when rerunning the script interactively

- No plugins, no MQTT, no Home Assistant required
  - Works standalone
  - Service-grade reliability

---

## Why AmpSwitch?

Most DIY amp control scripts:
- toggle relays on startup
- chatter between tracks
- break when switching players

AmpSwitch is edge-triggered, delay-aware, and player-agnostic — meaning:

The amp turns ON only when playback actually starts,  
and turns OFF only when playback really stops.

This matches the behavior of commercial audio controllers.

---

## Requirements

- Raspberry Pi (or compatible Linux SBC)
- GPIO-connected relay (optocoupled recommended)
- One of:
  - Volumio
  - Moode Audio
  - RuneAudio
  - Any MPD-based setup

Dependencies are installed automatically:
- gpiod
- curl, jq (Volumio)
- mpc (MPD)

---

## Installation

Copy the script to your device and run:

```bash
sudo bash ampswitch.sh
