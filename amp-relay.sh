#!/bin/bash
# =====================================================
# AmpSwitch INTERACTIVE (Volumio API + LONG off delay)
# Gap-proof approach: only turns OFF after OFF_DELAY seconds of NOT playing
# Interactive setup + test + systemd install + show config + uninstall
# =====================================================

INSTALL_DIR="/opt/ampswitch-simple"
CONF_FILE="$INSTALL_DIR/ampswitch.conf"
SERVICE_FILE="/etc/systemd/system/ampswitch-simple.service"
SCRIPT_NAME="ampswitch_interactive.sh"
SCRIPT_PATH="$(readlink -f "$0")"

RUNNING=1
IN_TEST=0

die(){ echo "ERROR: $*"; exit 1; }

command -v raspi-gpio >/dev/null 2>&1 || die "raspi-gpio not found"
command -v curl >/dev/null 2>&1 || die "curl not found"
command -v jq >/dev/null 2>&1 || die "jq not found"

on_int() {
  if [ "$IN_TEST" = "1" ]; then
    echo
    RUNNING=0
  else
    echo
    exit 0
  fi
}
trap on_int INT

# ---------- Volumio state ----------
get_state() {
  # returns: play | stop
  local s
  s="$(curl -s --max-time 1 http://localhost:3000/api/v1/getState | jq -r '.status' 2>/dev/null)"
  [ "$s" = "play" ] && echo "play" || echo "stop"
}

# ---------- GPIO helpers ----------
gpio_init() {
  raspi-gpio set "$GPIO" op
  raspi-gpio set "$GPIO" dl
}

pulse_ms() {
  local ms="$1"
  raspi-gpio set "$GPIO" dh
  sleep "$(awk -v m="$ms" 'BEGIN{printf "%.3f", (m/1000)}')"
  raspi-gpio set "$GPIO" dl
}

amp_on() {
  if [ "$MODE" = "toggle" ]; then
    pulse_ms "$PULSE_ON_MS"
  else
    raspi-gpio set "$GPIO" dh
  fi
}

amp_off() {
  if [ "$MODE" = "toggle" ]; then
    pulse_ms "$PULSE_OFF_MS"
  else
    raspi-gpio set "$GPIO" dl
  fi
}

# ---------- Core loop ----------
run_loop() {
  local amp=0
  local last_play
  last_play="$(date +%s)"

  gpio_init

  echo
  echo "AmpSwitch running:"
  echo "  GPIO=$GPIO  MODE=$MODE  OFF_DELAY=${OFF_DELAY}s  POLL=${POLL}s"
  if [ "$MODE" = "toggle" ]; then
    echo "  PULSE_ON_MS=$PULSE_ON_MS  PULSE_OFF_MS=$PULSE_OFF_MS"
  fi
  echo "CTRL+C to exit test mode"
  echo

  while true; do
    local state now
    state="$(get_state)"
    now="$(date +%s)"

    if [ "$state" = "play" ]; then
      last_play="$now"
      if [ "$amp" -eq 0 ]; then
        amp_on
        amp=1
        echo "AMP ON"
      fi
    else
      # Gap-proof OFF: only after long timeout
      if [ "$amp" -eq 1 ] && [ $((now - last_play)) -ge "$OFF_DELAY" ]; then
        amp_off
        amp=0
        echo "AMP OFF (no play for ${OFF_DELAY}s)"
      fi
    fi

    if [ "$IN_TEST" = "1" ] && [ "$RUNNING" -ne 1 ]; then
      break
    fi

    sleep "$POLL"
  done
}

# ---------- Config handling ----------
write_config() {
  sudo mkdir -p "$INSTALL_DIR" || die "Cannot create $INSTALL_DIR"
  sudo tee "$CONF_FILE" >/dev/null <<EOF
GPIO=$GPIO
MODE="$MODE"
PULSE_ON_MS=$PULSE_ON_MS
PULSE_OFF_MS=$PULSE_OFF_MS
OFF_DELAY=$OFF_DELAY
POLL=$POLL
EOF
}

show_config() {
  if [ ! -f "$CONF_FILE" ]; then
    echo "No config file found."
    return
  fi
  echo
  echo "===== Current config ($CONF_FILE) ====="
  cat "$CONF_FILE"
  echo "======================================="
  echo
}

install_service() {
  write_config

  sudo mkdir -p "$INSTALL_DIR" || die "Cannot create $INSTALL_DIR"
  sudo cp "$SCRIPT_PATH" "$INSTALL_DIR/$SCRIPT_NAME"
  sudo chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

  sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=AmpSwitch Simple Interactive (Volumio state, long OFF delay)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/bin/bash $INSTALL_DIR/$SCRIPT_NAME --service
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable ampswitch-simple
  sudo systemctl restart ampswitch-simple

  echo "Installed and started: ampswitch-simple.service"
}

uninstall_service() {
  echo "Uninstalling ampswitch-simple..."
  sudo systemctl stop ampswitch-simple 2>/dev/null || true
  sudo systemctl disable ampswitch-simple 2>/dev/null || true
  sudo rm -f "$SERVICE_FILE" 2>/dev/null || true
  sudo rm -rf "$INSTALL_DIR" 2>/dev/null || true
  sudo systemctl daemon-reload
  echo "Uninstalled."
}

# ---------- Service mode ----------
if [ "$1" = "--service" ]; then
  [ -f "$CONF_FILE" ] || die "Missing config: $CONF_FILE"
  # shellcheck disable=SC1090
  source "$CONF_FILE"
  IN_TEST=0
  trap '' INT
  run_loop
  exit 0
fi

# ---------- Installed menu ----------
if [ -f "$CONF_FILE" ] || systemctl list-unit-files 2>/dev/null | grep -q '^ampswitch-simple\.service'; then
  echo "AmpSwitch appears to be installed."
  echo "1) Reconfigure / Test"
  echo "2) Show current config"
  echo "3) Uninstall"
  echo "4) Exit"
  read -p "Choice [1]: " C
  C=${C:-1}
  case "$C" in
    2) show_config; exit 0 ;;
    3) uninstall_service; exit 0 ;;
    4) exit 0 ;;
  esac
fi

# =====================================================
# Interactive setup
# =====================================================

# Defaults (good for Spotify gaps)
GPIO=27
MODE="toggle"
PULSE_ON_MS=150
PULSE_OFF_MS=150
OFF_DELAY=180
POLL=1

echo
echo "=== AmpSwitch Interactive Setup ==="
echo "Tip: For Spotify gaps, use OFF_DELAY 180s (or 300s)."
echo

read -p "GPIO (BCM) [27]: " TMP
[ -n "$TMP" ] && GPIO="$TMP"
[[ "$GPIO" =~ ^[0-9]+$ ]] || die "GPIO must be a number"

echo
echo "Relay mode:"
echo "1) TOGGLE (power button pulse)  <-- your case"
echo "2) HOLD (GPIO high while playing)"
read -p "Choice [1]: " R
R=${R:-1}
[ "$R" = "2" ] && MODE="hold" || MODE="toggle"

if [ "$MODE" = "toggle" ]; then
  read -p "Pulse ON ms [150]: " TMP
  [ -n "$TMP" ] && PULSE_ON_MS="$TMP"
  read -p "Pulse OFF ms [150]: " TMP
  [ -n "$TMP" ] && PULSE_OFF_MS="$TMP"
fi

echo
read -p "OFF delay seconds (gap-proof) [180]: " TMP
[ -n "$TMP" ] && OFF_DELAY="$TMP"
[[ "$OFF_DELAY" =~ ^[0-9]+$ ]] || die "OFF_DELAY must be integer seconds"

read -p "Poll interval seconds [1]: " TMP
[ -n "$TMP" ] && POLL="$TMP"
[[ "$POLL" =~ ^[0-9]+$ ]] || die "POLL must be integer seconds"

echo
echo "=== TEST MODE ==="
echo "Play music / change tracks / pause. CTRL+C to stop test."
RUNNING=1
IN_TEST=1
run_loop
IN_TEST=0

echo
read -p "Install as service? (y/N): " Q
if [ "$Q" = "y" ]; then
  install_service
else
  echo "Not installed. (You can run it anytime with: sudo ./$SCRIPT_NAME)"
fi

echo "Done."