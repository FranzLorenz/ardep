#!/usr/bin/env bash
#
# Upload a compiled Arduino sketch to ARDEP's user_sketch partition via the
# on-board Black Magic Probe. Invoked by the `bmp` upload tool defined in
# platform.local.txt, so it works from `arduino-cli upload` and the Arduino IDE
# "Upload" button.
#
#   bmp-upload.sh <gdb-serial-port> <sketch-artifact> [user_sketch-address]
#
# BMP refuses raw `restore` to flash, so the sketch binary is converted to ihex
# at the user_sketch address and programmed with GDB `load`, then the target is
# reset so the loader picks up the new sketch.
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

PORT="${1:?gdb serial port (e.g. /dev/cu.usbmodemXXXX1)}"
ARTIFACT="${2:?sketch artifact (.elf-zsk.bin)}"
ADDR="${3:-0x08050000}"

SDK="${ZEPHYR_SDK_INSTALL_DIR:-$HOME/zephyr-sdk-0.16.8}"
GDB="$SDK/arm-zephyr-eabi/bin/arm-zephyr-eabi-gdb"
OBJCOPY="$SDK/arm-zephyr-eabi/bin/arm-zephyr-eabi-objcopy"

[ -x "$GDB" ] || { echo "arm-zephyr-eabi-gdb not found at $GDB (set ZEPHYR_SDK_INSTALL_DIR)"; exit 1; }
[ -f "$ARTIFACT" ] || { echo "sketch artifact not found: $ARTIFACT"; exit 1; }

HEX="$(mktemp -t ardep_upload).hex"
trap 'rm -f "$HEX"' EXIT
"$OBJCOPY" -I binary -O ihex --change-addresses "$ADDR" "$ARTIFACT" "$HEX"

"$GDB" --batch \
  -ex "set pagination off" -ex "set confirm off" \
  -ex "target extended-remote $PORT" \
  -ex "monitor swdp_scan" \
  -ex "attach 1" \
  -ex "load $HEX" \
  -ex "monitor reset" \
  -ex "kill"

echo "Uploaded $(basename "$ARTIFACT") to user_sketch ($ADDR) and reset."
