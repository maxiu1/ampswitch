# AmpSwitch

Simple, reliable amplifier power control for Volumio using Raspberry Pi GPIO.

AmpSwitch monitors Volumio playback state and controls a relay (or relays) to:
- turn an amplifier ON when music starts
- turn it OFF after music stops (with delay)
- avoid relay chatter during track changes

This script is designed for real hardware, not demos.

---

## Key Features

- Volumio-native GPIO control  
  - Uses raspi-gpio only (no sysfs, no gpiod)  
  - Matches how Volumio plugins handle GPIO  
  - Works reliably on Volumio 3.x and newer  

- Edge-triggered playback detection  
  - Relay turns ON only on STOP → PLAY  
  - Relay turns OFF only after confirmed stop + delay  

- Relay modes  
  - Toggle mode – pulse relay to emulate a power button  
  - Hold mode – keep relay ON while music is playing  

- Stop delay  
  - Prevents relay chatter during:  
    - track changes  
    - Spotify gaps  
    - radio buffering  

- Interactive test mode  
  - Safe testing without installing a service  
  - CTRL+C exits test mode and returns to menu  

- Systemd service support  
  - Optional background service  
  - Starts automatically on boot  

- Built-in management  
  - Reconfigure / Test  
  - Show current active config  
  - Uninstall (clean removal)  

---

## Requirements

- Raspberry Pi  
- Volumio OS  
- GPIO relay module  
- raspi-gpio (included with Volumio)  
- curl and jq (included with Volumio)  

This script intentionally does NOT use:
- /sys/class/gpio  
- libgpiod  
- MQTT  
- Home Assistant  

---

## Installation / Usage

### 1. Run interactively (recommended first)

sudo ./ampswitch.sh

You will be guided through:
- relay mode selection  
- GPIO pin selection  
- pulse durations  
- stop delay  
- poll interval  

Then the script enters TEST MODE.

---

### 2. Test mode

During test mode:
- Play / stop music in Volumio  
- Watch the relay behavior  
- Press CTRL+C to exit test mode  

After exiting test mode, you can:
- adjust settings again  
- install as a systemd service  
- exit without installing  

---

### 3. Install as service

If you choose to install:
- configuration is saved to /opt/ampswitch/ampswitch.conf  
- service file is created: ampswitch.service  
- service starts automatically on boot  

Check status:

systemctl status ampswitch

View logs:

journalctl -u ampswitch

---

## Management Menu (when already installed)

Re-running the script shows:

AmpSwitch appears to be installed.
1) Reconfigure / Test
2) Show current config
3) Uninstall
4) Exit

### Show current config
Displays the exact configuration used by the service.

### Uninstall
- Stops and disables the service  
- Removes all installed files  
- Leaves your system clean  

---

## Safety Notes

- Use optocoupled relay modules  
- Never connect GPIO directly to mains voltage  
- Only one process should control a GPIO pin  
- Do not share GPIO pins with other Volumio plugins  

---

## Why raspi-gpio only?

On Volumio:
- sysfs GPIO is unreliable or disabled  
- gpiod may be unavailable on older releases  
- raspi-gpio is stable, native, and intended for this use  

This script follows Volumio’s real GPIO constraints, not generic Linux assumptions.

---

## License

MIT License  
Use it, modify it, share it.

---

## Author

Created and tested by Marcin  
Built through real-world testing on Volumio with physical amplifiers and relays.