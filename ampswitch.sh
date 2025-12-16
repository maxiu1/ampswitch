#!/bin/bash

# =====================================================
# AmpSwitch — Universal Amp Controller
# FIX: Robust Volumio detection (no false MPD fallback)
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

# ---------- PLAYER AUTO-DETECT (FIXED) ----------
detect_player() {
  # ---- Strong Volumio detection ----
  if [ -d /volumio ] || \
     [ -f /data/configuration/core/state.json ] || \
     systemctl list-units --type=service | grep -q volumio.service; then
    PLAYER_TYPE="volumio"
    return
  fi

  # ---- Fallback to MPD ----
  if need_cmd mpc; then
    PLAYER_TYPE="mpd"
    return
  fi

  PLAYER_TYPE="none"
}

# ---------- PLAYER STATE ----------
get_state() {
  if [ "$PLAYER_TYPE" = "volumio" ]; then
    local s
    s="$(curl -s --max-time 1 http://localhost:3000/api/v1/getState | jq -r '.status' 2>/dev/null)"
    [ "$s" = "play" ] && echo "play" || echo "stop"
    return
  fi

  if [ "$PLAYER_TYPE" = "mpd" ]; then
    mpc status 2>/dev/null | grep -q "\[playing\]" && echo "play" || echo "stop"
    return
  fi

  echo "stop"
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
  STOP_CANDIDATE_MS=0
  STARTUP_IGNORE=1
  RUNNING=1

  detect_player
  echo "AmpSwitch running (mode=$MODE, player=$PLAYER_TYPE)"

  if [ "$MODE" = "service" ] && [ "$FORCE_OFF_ON_START" = "1" ]; then
    force_off
  fi

  while [ "$RUNNING" -eq 1 ]; do
    STATE="$(get_state)"
    NOW="$(now_ms)"

    if [ "$STARTUP_IGNORE" = "1" ]; then
      PREV_STATE="$STATE"
      STARTUP_IGNORE=0
      sleep_ms "$POLL_MS"
      continue
    fi

    # PLAY edge
    if [ "$STATE" = "play" ] && [ "$PREV_STATE" != "play" ]; then
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

    # STOP candidate
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

# ---------- INTERACTIVE MODE ----------
echo
echo "=== TEST MODE ==="
echo "Play / stop music. CTRL+C to exit."
install_deps
run_main_loop
