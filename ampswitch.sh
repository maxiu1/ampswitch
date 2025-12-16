#!/bin/bash

# =====================================================
# AmpSwitch — Universal Amp Controller
# Players: Volumio / MPD (auto-detect)
# Relay modes: toggle / hold
# =====================================================

SCRIPT_PATH="$(readlink -f "$0")"
INSTALL_DIR="/opt/ampswitch"
CONF_FILE="$INSTALL_DIR/ampswitch.conf"
SERVICE_FILE="/etc/systemd/system/ampswitch.service"

RUNNING=1
MODE="interactive"

# ---------- SIGNAL ----------
on_interrupt() {
  echo
  RUNNING=0
}
trap on_interrupt INT

# ---------- HELPERS ----------
need_cmd() { command -v "$1" >/dev/null 2>&1; }
now_ms() { date +%s%3N; }
sleep_ms() { sleep "$(awk "BEGIN {print $1/1000}")"; }

# ---------- DEPENDENCIES ----------
install_deps() {
  PKGS=(gpiod curl jq mpc)
  sudo apt update
  sudo apt install -y "${PKGS[@]}"
}

# ---------- GPIO ----------
pulse_gpio() {
  local gpio=$1 dur=$2
  gpioset gpiochip0 "$gpio=$ON"
  sleep_ms "$dur"
  gpioset gpiochip0 "$gpio=$OFF"
}

set_gpio() {
  local gpio=$1 val=$2
  gpioset gpiochip0 "$gpio=$val"
}

# ---------- PLAYER AUTO-DETECT ----------
detect_player() {
  if curl -s --max-time 1 http://localhost:3000/api/v1/getState >/dev/null; then
    PLAYER_TYPE="volumio"
  elif need_cmd mpc; then
    PLAYER_TYPE="mpd"
  else
    PLAYER_TYPE="none"
  fi
}

# ---------- PLAYER STATE ----------
get_state() {
  if [ "$PLAYER_TYPE" = "volumio" ]; then
    local s
    s="$(curl -s http://localhost:3000/api/v1/getState | jq -r '.status' 2>/dev/null)"
    [ "$s" = "play" ] && echo "play" || echo "stop"
  elif [ "$PLAYER_TYPE" = "mpd" ]; then
    mpc status 2>/dev/null | grep -q "\[playing\]" && echo "play" || echo "stop"
  else
    echo "stop"
  fi
}

# ---------- FORCE OFF ----------
force_off() {
  for ((i=${#GPIOS[@]}-1; i>=0; i--)); do
    if [ "$RELAY_MODE" = "toggle" ]; then
      pulse_gpio "${GPIOS[$i]}" "$PULSE_OFF_MS"
    else
      set_gpio "${GPIOS[$i]}" "$OFF"
    fi
    sleep_ms "$SEQ_DELAY_MS"
  done
}

# ---------- MAIN LOOP ----------
run_main_loop() {
  AMP_ON=0
  PREV_STATE=""
  LAST_PLAY_MS=0
  STOP_CANDIDATE_MS=0
  STARTUP_IGNORE=1
  RUNNING=1

  detect_player
  echo "AmpSwitch running (mode=$MODE, player=$PLAYER_TYPE)"

  # ✅ Force OFF ONLY for service
  if [ "$MODE" = "service" ] && [ "$FORCE_OFF_ON_START" = "1" ]; then
    force_off
  fi

  while [ "$RUNNING" -eq 1 ]; do
    STATE="$(get_state)"
    NOW="$(now_ms)"

    # ---- Startup guard ----
    if [ "$STARTUP_IGNORE" = "1" ]; then
      PREV_STATE="$STATE"
      STARTUP_IGNORE=0
      sleep_ms "$POLL_MS"
      continue
    fi

    # ---- PLAY edge ----
    if [ "$STATE" = "play" ]; then
      LAST_PLAY_MS="$NOW"
      STOP_CANDIDATE_MS=0

      if [ "$AMP_ON" -eq 0 ] && [ "$PREV_STATE" != "play" ]; then
        for i in "${!GPIOS[@]}"; do
          if [ "$RELAY_MODE" = "toggle" ]; then
            pulse_gpio "${GPIOS[$i]}" "$PULSE_ON_MS"
          else
            set_gpio "${GPIOS[$i]}" "$ON"
          fi
          sleep_ms "$SEQ_DELAY_MS"
        done
        AMP_ON=1
      fi
    fi

    # ---- STOP candidate ----
    if [ "$STATE" != "play" ] && [ "$AMP_ON" -eq 1 ]; then
      [ "$STOP_CANDIDATE_MS" -eq 0 ] && STOP_CANDIDATE_MS="$NOW"

      if [ $((NOW - STOP_CANDIDATE_MS)) -ge "$STOP_DELAY_MS" ]; then
        force_off
        AMP_ON=0
        STOP_CANDIDATE_MS=0
      fi
    fi

    PREV_STATE="$STATE"
    sleep_ms "$POLL_MS"
  done
}

# ---------- SERVICE MODE ----------
if [ "$1" = "--service" ]; then
  MODE="service"
  source "$CONF_FILE"
  install_deps
  trap '' INT
  run_main_loop
  exit 0
fi

# =====================================================
# INTERACTIVE MODE
# =====================================================

# ---------- Existing install ----------
if [ -f "$CONF_FILE" ]; then
  echo "AmpSwitch already installed."
  echo "1) Reconfigure / Test"
  echo "2) Uninstall"
  echo "3) Exit"
  read -p "Choice [1]: " C
  C=${C:-1}

  if [ "$C" = "2" ]; then
    sudo systemctl stop ampswitch 2>/dev/null
    sudo systemctl disable ampswitch 2>/dev/null
    sudo rm -f "$SERVICE_FILE"
    sudo rm -rf "$INSTALL_DIR"
    sudo systemctl daemon-reload
    echo "Removed."
    exit 0
  elif [ "$C" = "3" ]; then
    exit 0
  fi
fi

# ---------- SETUP ----------
STOP_DELAY_MS=5000
POLL_MS=300
ON=1
OFF=0
RELAY_MODE="toggle"
SEQ_DELAY_MS=300
FORCE_OFF_ON_START=1

install_deps

echo "Relay behavior:"
echo "1) Toggle (pulse ON / pulse OFF)"
echo "2) Hold (relay ON while playing)"
read -p "Choice [1]: " R
[ "$R" = "2" ] && RELAY_MODE="hold"

read -p "Force amp OFF on service startup? (Y/n): " F
[ "$F" = "n" ] && FORCE_OFF_ON_START=0

read -p "Use multiple relays? (y/N): " M
if [ "$M" = "y" ]; then
  read -p "How many relays?: " RELAY_COUNT
  read -p "Delay between relays (ms) [300]: " TMP
  [ -n "$TMP" ] && SEQ_DELAY_MS="$TMP"
else
  RELAY_COUNT=1
  SEQ_DELAY_MS=0
fi

GPIOS=()
for ((i=0;i<RELAY_COUNT;i++)); do
  read -p "GPIO for relay $((i+1)): " G
  GPIOS+=("$G")
done

read -p "Pulse ON duration (ms) [150]: " TMP
PULSE_ON_MS=${TMP:-150}

read -p "Pulse OFF duration (ms) [150]: " TMP
PULSE_OFF_MS=${TMP:-150}

read -p "Stop delay before OFF (ms) [5000]: " TMP
[ -n "$TMP" ] && STOP_DELAY_MS="$TMP"

read -p "Poll interval (ms) [300]: " TMP
[ -n "$TMP" ] && POLL_MS="$TMP"

# ---------- TEST ----------
echo
echo "=== TEST MODE ==="
echo "Play / stop music. CTRL+C to exit."
run_main_loop

# ---------- INSTALL ----------
read -p "Install as service? (y/N): " Q
[ "$Q" != "y" ] && exit 0

sudo mkdir -p "$INSTALL_DIR"
sudo tee "$CONF_FILE" >/dev/null <<EOF
STOP_DELAY_MS=$STOP_DELAY_MS
POLL_MS=$POLL_MS
ON=$ON
OFF=$OFF
RELAY_MODE="$RELAY_MODE"
FORCE_OFF_ON_START=$FORCE_OFF_ON_START
SEQ_DELAY_MS=$SEQ_DELAY_MS
GPIOS=(${GPIOS[@]})
PULSE_ON_MS=$PULSE_ON_MS
PULSE_OFF_MS=$PULSE_OFF_MS
EOF

sudo cp "$SCRIPT_PATH" "$INSTALL_DIR/ampswitch.sh"
sudo chmod +x "$INSTALL_DIR/ampswitch.sh"

sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=AmpSwitch
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$INSTALL_DIR/ampswitch.sh --service
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ampswitch
sudo systemctl restart ampswitch

echo "✅ Installed and running"
