#!/usr/bin/env bash
#
# Flash the Arduino loader + a compiled sketch onto ARDEP via the on-board
# Black Magic Probe (BMP), over USB-C. No external probe needed.
#
# ARDEP v2's on-board debugger is a Black Magic Probe (it enumerates as two
# USB CDC serial ports: the lower one is the GDB server, the higher is the
# target UART). Flashing goes through GDB; raw `restore` to flash is refused
# by BMP, so the sketch binary is converted to ihex and programmed with `load`.
#
# Verified working 2026-06-02: red LED blink on real hardware.
#
# Usage:
#   arduino/flash/flash-bmp.sh <gdb-serial-port> <loader.elf> <sketch.elf-zsk.bin>
# Example:
#   arduino/flash/flash-bmp.sh /dev/cu.usbmodemXXXX1 \
#     ~/.../build/ardep_stm32g474xx/zephyr/zephyr.elf \
#     ~/.../build/arduino-git.zephyr.ardep/blink.ino.elf-zsk.bin
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

PORT="${1:?GDB serial port, e.g. /dev/cu.usbmodemXXXX1}"
LOADER="${2:?path to loader zephyr.elf}"
SKETCH="${3:?path to sketch .elf-zsk.bin}"

SDK="${ZEPHYR_SDK_INSTALL_DIR:-$HOME/zephyr-sdk-0.16.8}"
GDB="$SDK/arm-zephyr-eabi/bin/arm-zephyr-eabi-gdb"
OBJCOPY="$SDK/arm-zephyr-eabi/bin/arm-zephyr-eabi-objcopy"
USER_SKETCH_ADDR=0x08050000
BACKUP="${BACKUP:-$HOME/ardep-flash-backup/backup.bin}"

mkdir -p "$(dirname "$BACKUP")"

echo ">> 1/4 Backup full 512K flash -> $BACKUP (anti-brick)"
"$GDB" --batch -ex "set pagination off" -ex "set confirm off" \
  -ex "target extended-remote $PORT" -ex "monitor swdp_scan" -ex "attach 1" \
  -ex "dump binary memory $BACKUP 0x08000000 0x08080000"
[ "$(stat -f%z "$BACKUP" 2>/dev/null || stat -c%s "$BACKUP")" = "524288" ] || {
  echo "Backup size unexpected — aborting." >&2; exit 1; }

echo ">> 2/4 Flash loader: $LOADER"
"$GDB" --batch -ex "set pagination off" -ex "set confirm off" \
  -ex "target extended-remote $PORT" -ex "monitor swdp_scan" -ex "attach 1" \
  -ex "load $LOADER" -ex "kill"

echo ">> 3/4 Flash sketch -> user_sketch ($USER_SKETCH_ADDR)"
HEX="$(mktemp -t ardep_sketch).hex"
"$OBJCOPY" -I binary -O ihex --change-addresses "$USER_SKETCH_ADDR" "$SKETCH" "$HEX"
"$GDB" --batch -ex "set pagination off" -ex "set confirm off" \
  -ex "target extended-remote $PORT" -ex "monitor swdp_scan" -ex "attach 1" \
  -ex "load $HEX" -ex "kill"
rm -f "$HEX"

echo ">> 4/4 Reset"
"$GDB" --batch -ex "set pagination off" -ex "set confirm off" \
  -ex "target extended-remote $PORT" -ex "monitor swdp_scan" -ex "attach 1" \
  -ex "monitor reset" -ex "kill"

echo ">> Done. To restore the original firmware (BMP needs ihex, not raw load):"
echo "   $OBJCOPY -I binary -O ihex --change-addresses 0x08000000 $BACKUP /tmp/restore.hex"
echo "   $GDB --batch -ex 'target extended-remote $PORT' -ex 'monitor swdp_scan' \\"
echo "        -ex 'attach 1' -ex 'load /tmp/restore.hex' -ex 'monitor reset' -ex 'kill'"
