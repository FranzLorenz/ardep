#!/usr/bin/env bash
#
# Red-Green test for ARDEP Arduino support.
# GREEN = the loader builds AND the blink sketch compiles against it.
# Run this before every commit; CI runs the same.
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

ARDEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="${ARDUINO_CORE:-$HOME/code/arduino-zephyr/modules/lib/ArduinoCore-zephyr}"
FQBN="${FQBN:-arduino-git:zephyr:ardep}"

red() { printf '\033[31mRED: %s\033[0m\n' "$1" >&2; exit 1; }

[ -d "$CORE" ] || red "ArduinoCore-zephyr not found at $CORE (set ARDUINO_CORE)"

echo "== 1/3 Lint =="
if command -v shellcheck >/dev/null 2>&1; then
	shellcheck "$ARDEP_DIR"/arduino/*.sh || red "shellcheck failed"
else
	echo "   (shellcheck not installed — skipping)"
fi
if command -v dtc >/dev/null 2>&1; then
	# Sanity: overlay must parse as devicetree fragment (best-effort).
	dtc -I dts -O dtb -o /dev/null "$ARDEP_DIR/arduino/variant/ardep.overlay" 2>/dev/null \
		|| echo "   (overlay is a fragment; standalone dtc parse skipped)"
fi

echo "== 2/3 Build loader =="
export ARDEP_DIR
( cd "$CORE" && bash "$ARDEP_DIR/arduino/build-loader.sh" ) \
	|| red "loader build failed"

echo "== 3/3 Compile example sketches =="
command -v arduino-cli >/dev/null 2>&1 || red "arduino-cli not installed"
for ex in blink peripherals; do
	echo "   - $ex"
	arduino-cli compile -b "$FQBN" "$ARDEP_DIR/arduino/examples/$ex" \
		|| red "$ex sketch failed to compile"
done

printf '\033[32mGREEN: loader builds + example sketches compile\033[0m\n'
