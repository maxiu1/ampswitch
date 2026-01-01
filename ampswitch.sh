#!/bin/bash
# =====================================================
# AmpSwitch — Volumio GPIO Amp Controller
# GPIO backend: raspi-gpio ONLY
# CTRL+C exits test mode and returns to menu
# Includes: reconfigure / show config / uninstall
# =====================================================

INSTALL_DIR="/opt/ampswitch"
CONF_FILE="$INSTALL_DIR/ampswitch.conf"
SERVICE_FILE="/etc/systemd/system/ampswitch.service"
SCRIPT_PATH="$(readlink -f "$0")"

RUNNING=1
IN_TEST=0

# ---------- helpers ----------
now_ms() { date +%s%3N; }

sleep_ms() {
  local ms="$1"
  [[ "$ms" =~ ^[0-9]+$ ]] || return
  [ "$ms" -gt 0 ] || return
  sleep "$(printf "0.%03d" "$ms")"
}

die() { echo "ERROR: $*"; exit 1; }

# ---------- CTRL+C behavior ----------
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

# ---------- checks ----------
command -v raspi-gpio >/dev/null 2>&1 || die "raspi-gpio not found (Volumio required)"
command -v curl >/dev/null 2>&1 || die "curl not found"
command -v jq >/dev/null 2>&1 || die "jq not found"

# ---------- gpio ----------
gpio_init() {
  for g in "${GPIOS[@]}"; do
    raspi-gpio set "$g" op
    raspi-gpio set "$g" dl
  done
}

gpio_set() {
  if [ "$2" = "1" ]; then
    raspi-gpio set "$1" dh
  else
    raspi-gpio set "$1" dl
  fi
}

gpio_pulse() {
  gpio_set "$1" 1
  sleep_ms "$2"
  gpio_set "$1" 0
}

# ---------- volumio state ----------
get_state() {
  local s
  s="$(curl -s --max-time 1 http://localhost:3000/api/v1/getState \
      | jq -r '.status' 2>/dev/null)"
  [ "$s" = "play" ] && echo play || echo stop
}

# ---------- force off ----------
force_off() {
  for ((i=${#GPIOS[@]}-1;i>=0;i--)); do
    if [ "$RELAY_MODE" = "toggle" ]; then
      gpio_pulse "${GPIOS[$i]}" "$PULSE_OFF_MS"
    else
      gpio_set "${GPIOS[$i]}" 0
    fi
    sleep_ms "$SEQ_DELAY_MS"
  done
}

# ---------- main loop ----------
run_main_loop() {
  local AMP_ON=0
  local PREV_STATE=""
  local STOP_CANDIDATE_MS=0
  local STARTUP_IGNORE=1

  RUNNING=1
  IN_TEST=1

  gpio_init
  echo "AmpSwitch running (player=volumio, gpio=raspi)"
  echo "CTRL+C = exit test mode"

  while [ "$RUNNING" -eq 1 ]; do
    STATE="$(get_state)"
    NOW="$(now_ms)"

    if [ "$STARTUP_IGNORE" = "1" ]; then
      PREV_STATE="$STATE"
      STARTUP_IGNORE=0
      sleep_ms "$POLL_MS"
      continue
    fi

    if [ "$STATE" = "play" ] && [ "$PREV_STATE" != "play" ]; then
      for g in "${GPIOS[@]}"; do
        if [ "$RELAY_MODE" = "toggle" ]; then
          gpio_pulse "$g" "$PULSE_ON_MS"
        else
          gpio_set "$g" 1
        fi
        sleep_ms "$SEQ_DELAY_MS"
      done
      AMP_ON=1
    fi

    if [ "$STATE" != "play" ] && [ "$AMP_ON" -eq 1 ]; then
      [ "$STOP_CANDIDATE_MS" -eq 0 ] && STOP_CANDIDATE_MS="$NOW"
      if [ $((NOW - STOP_CANDIDATE_MS)) -ge "$STOP_DELAY_MS" ]; then
        force_off
        AMP_ON=0
        STOP_CANDIDATE_MS=0
      fi
    fi

    [ "$STATE" = "play" ] && STOP_CANDIDATE_MS=0
    PREV_STATE="$STATE"
    sleep_ms "$POLL_MS"
  done

  IN_TEST=0
}

# ---------- show config ----------
show_config() {
  if [ ! -f "$CONF_FILE" ]; then
    echo "No config file found."
    return
  fi

  echo
  echo "===== AmpSwitch current config ====="
  cat "$CONF_FILE"
  echo "===================================="
  echo
}

# ---------- uninstall ----------
uninstall_service() {
  echo "Uninstalling AmpSwitch..."

  sudo systemctl stop ampswitch >/dev/null 2>&1 || true
  sudo systemctl disable ampswitch >/dev/null 2>&1 || true
  sudo rm -f "$SERVICE_FILE" >/dev/null 2>&1 || true
  sudo rm -rf "$INSTALL_DIR" >/dev/null 2>&1 || true
  sudo systemctl daemon-reload >/dev/null 2>&1 || true

  echo "Uninstalled."
}

# ---------- service install ----------
install_service() {
  sudo mkdir -p "$INSTALL_DIR" || return 1

  sudo tee "$CONF_FILE" >/dev/null <<EOF
RELAY_MODE="$RELAY_MODE"
SEQ_DELAY_MS=$SEQ_DELAY_MS
STOP_DELAY_MS=$STOP_DELAY_MS
POLL_MS=$POLL_MS
GPIOS=(${GPIOS[@]})
PULSE_ON_MS=$PULSE_ON_MS
PULSE_OFF_MS=$PULSE_OFF_MS
EOF

  sudo cp "$SCRIPT_PATH" "$INSTALL_DIR/ampswitch.sh"
  sudo chmod +x "$INSTALL_DIR/ampswitch.sh"

  sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=AmpSwitch (Volumio, raspi-gpio)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/bin/bash $INSTALL_DIR/ampswitch.sh --service
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable ampswitch
  sudo systemctl restart ampswitch

  echo "Installed and started: ampswitch.service"
}

# ---------- service mode ----------
if [ "$1" = "--service" ]; then
  [ -f "$CONF_FILE" ] || die "Missing config: $CONF_FILE"
  source "$CONF_FILE"

  gpio_init
  trap '' INT

  AMP_ON=0
  PREV_STATE=""
  STOP_CANDIDATE_MS=0
  STARTUP_IGNORE=1

  while true; do
    STATE="$(get_state)"
    NOW="$(now_ms)"

    if [ "$STARTUP_IGNORE" = "1" ]; then
      PREV_STATE="$STATE"
      STARTUP_IGNORE=0
      sleep_ms "$POLL_MS"
      continue
    fi

    if [ "$STATE" = "play" ] && [ "$PREV_STATE" != "play" ]; then
      for g in "${GPIOS[@]}"; do
        if [ "$RELAY_MODE" = "toggle" ]; then
          gpio_pulse "$g" "$PULSE_ON_MS"
        else
          gpio_set "$g" 1
        fi
        sleep_ms "$SEQ_DELAY_MS"
      done
      AMP_ON=1
    fi

    if [ "$STATE" != "play" ] && [ "$AMP_ON" -eq 1 ]; then
      [ "$STOP_CANDIDATE_MS" -eq 0 ] && STOP_CANDIDATE_MS="$NOW"
      if [ $((NOW - STOP_CANDIDATE_MS)) -ge "$STOP_DELAY_MS" ]; then
        force_off
        AMP_ON=0
        STOP_CANDIDATE_MS=0
      fi
    fi

    [ "$STATE" = "play" ] && STOP_CANDIDATE_MS=0
    PREV_STATE="$STATE"
    sleep_ms "$POLL_MS"
  done
fi

# =====================================================
# Installed menu
# =====================================================
if [ -f "$CONF_FILE" ] || systemctl list-unit-files 2>/dev/null | grep -q '^ampswitch\.service'; then
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
# Interactive setup loop
# =====================================================
while true; do
  RELAY_MODE="toggle"
  SEQ_DELAY_MS=300
  STOP_DELAY_MS=5000
  POLL_MS=300

  echo
  echo "Relay mode:"
  echo "1) Toggle (power button)"
  echo "2) Hold (relay ON while playing)"
  read -p "Choice [1]: " R
  [ "$R" = "2" ] && RELAY_MODE="hold"

  read -p "GPIO for relay: " G
  GPIOS=("$G")

  read -p "Pulse ON ms [150]: " TMP
  PULSE_ON_MS=${TMP:-150}

  read -p "Pulse OFF ms [150]: " TMP
  PULSE_OFF_MS=${TMP:-150}

  read -p "Stop delay ms [5000]: " TMP
  [ -n "$TMP" ] && STOP_DELAY_MS="$TMP"

  read -p "Poll interval ms [300]: " TMP
  [ -n "$TMP" ] && POLL_MS="$TMP"

  echo
  echo "=== TEST MODE ==="
  echo "Play / stop music. CTRL+C to exit test mode."
  run_main_loop

  echo
  read -p "Adjust settings again? (y/N): " A
  [ "$A" = "y" ] && continue

  read -p "Install as service? (y/N): " Q
  [ "$Q" = "y" ] && install_service

  echo "Done."
  exit 0
done
