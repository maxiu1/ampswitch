# 🔊 amp-relay.sh  
**Volumio GPIO Amplifier Relay Controller (Gap-Proof)**

A simple and reliable Bash script that controls an amplifier relay using GPIO based on Volumio playback state.

Designed specifically to eliminate the infamous **Spotify / Volumio track-gap bug**, where the player briefly reports `stop` between tracks and accidentally turns the amp off.

Instead of reacting instantly, the amp turns OFF only after a long configurable delay.

---

## ✨ Features

- 🔌 GPIO relay control (BCM numbering)
- 🎛 Two relay modes:
  - **toggle** – pulse like a power button
  - **hold** – GPIO stays HIGH while playing
- ⏱ Configurable OFF delay (gap-proof)
- ⚙ Interactive setup wizard
- 🧪 Test mode before installing
- 🚀 Optional systemd service installation
- 🧹 Built-in uninstall option
- 📜 Minimal dependencies
- 🧠 Designed for stability over complexity

---

## 🧱 Requirements

- Raspberry Pi running Volumio / Linux
- Bash
- `raspi-gpio`
- `curl`
- `jq`

Install dependencies if missing:

```bash
sudo apt update
sudo apt install -y curl jq