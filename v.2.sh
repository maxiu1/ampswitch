#!/bin/bash

# =====================================================
# AmpSwitch — Volumio GPIO Amp Controller
# GPIO backend: raspi-gpio ONLY
# =====================================================

MODE="interactive"
RUNNING=1

trap 'RUNNING=0' INT

# -----------------------------------------------------
# Helpers
# -----------------------------------------------------
now_ms() {
  date +%s%3N
}

sleep_ms() {
  local ms="$1"
  [[ "$ms" =~ ^[0-9]+$ ]] || return
  [ "$ms" -gt 0 ] || return
  sleep "$(printf "0.%03d" "$ms")"
}

# -----------------------------------------------------
# Check dependency (Volumio native)
# -----------------------------------------------------
if ! command -v raspi-gpio >/dev/null 2>&1; then
  echo "ERROR: raspi-gpio not found. This script is for Volumio."
  exit 1
fi

# -----------------------------------------------------
# GPIO helpers (raspi-gpio)
# -----------------------------------------------------
gpio_init() {
  for g in "${GPIOS[@]}"; do
    raspi-gpio set "$g" op
    raspi-gpio set "$g" dl
  done
}

gpio_set() {
  local g="$1" v="$2"
  if [ "$v" = "1" ]; then
    raspi-gpio set "$g" dh
  else
    raspi-gpio set "$g" dl
  fi
}

gpio_pulse() {
  gpio_set "$1" 1
  sleep_ms "$2"
  gpio_set "$1" 0
}

# -----------------------------------------------------
# Player detection (Volumio)
# -----------------------------------------------------
detect_player() {
  if [ -d /volumio ] || [ -f /data/configuration/core/state.json ]; then
    PLAYER_TYPE="volumio"
  else
    PLAYER_TYPE="none"
  fi
}

# -----------------------------------------------------
# Player state
# -----------------------------------------------------
get_state() {
  local s
  s="$(curl -s --max-time 1 http://localhost:3000/api/v1/getState \
      | jq -r '.status' 2>/dev/null)"
  [ "$s" = "play" ] && echo play || echo stop
}

# -----------------------------------------------------
# Force OFF
# -----------------------------------------------------
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

# -----------------------------------------------------
# Main loop
# -----------------------------------------------------
run_main_loop() {
  AMP_ON=0
  PREV_STATE=""
  STOP_CANDIDATE_MS=0
  STARTUP_IGNORE=1

  detect_player
  gpio_init

  echo "AmpSwitch running (player=$PLAYER_TYPE, gpio=raspi)"

  while [ "$RUNNING" -eq 1 ]; do
    STATE="$(get_state)"
    NOW="$(now_ms)"

    # ignore initial state
    if [ "$STARTUP_IGNORE" = "1" ]; then
      PREV_STATE="$STATE"
      STARTUP_IGNORE=0
      sleep_ms "$POLL_MS"
      continue
    fi

    # PLAY edge
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

    # STOP delay
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

# =====================================================
# INTERACTIVE SETUP
# =====================================================

RELAY_MODE="toggle"
SEQ_DELAY_MS=300
STOP_DELAY_MS=5000
POLL_MS=300

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
echo "Play / stop music. CTRL+C to exit."
run_main_loop