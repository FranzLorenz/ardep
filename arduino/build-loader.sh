#!/usr/bin/env bash
#
# Build the Arduino-for-Zephyr loader for the ARDEP board and post-process it
# into a complete variant (EDK + symbol scripts + arduino cflags) so sketches
# can be compiled against it.
#
# This replaces upstream `extra/build.sh ardep`, which cannot find ARDEP: its
# variant-name probe uses `find_package(Zephyr COMPONENTS boards)`, a mode that
# does not process board_root from an out-of-tree module's module.yml. We pass
# BOARD_ROOT + ZEPHYR_EXTRA_MODULES explicitly instead.
#
# Run from the ArduinoCore-zephyr core root (where platform.txt lives), with
# the venv available. Override paths via env if your layout differs.
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

VARIANT=ardep_stm32g474xx
BOARD=ardep

ARDEP_DIR="${ARDEP_DIR:-$HOME/code/ardep}"
EXTRA_MODULES_DIR="${EXTRA_MODULES_DIR:-$HOME/code/arduino-zephyr/extra-modules}"
EM="$ARDEP_DIR;$EXTRA_MODULES_DIR/zephyrboards;$EXTRA_MODULES_DIR/iso14229;$EXTRA_MODULES_DIR/cannectivity"

if [ ! -f platform.txt ]; then
	echo "Run this from the ArduinoCore-zephyr core root." >&2
	exit 2
fi

# shellcheck disable=SC1091  # venv created at runtime, not available to linter
source venv/bin/activate
ZEPHYR_BASE="$(west topdir)/zephyr"
export ZEPHYR_BASE

BUILD_DIR="build/${VARIANT}"
VARIANT_DIR="variants/${VARIANT}"

echo ">> Syncing variant source files from fork"
mkdir -p "${VARIANT_DIR}"
cp "${ARDEP_DIR}/arduino/variant/ardep.overlay" "${VARIANT_DIR}/${VARIANT}.overlay"
cp "${ARDEP_DIR}/arduino/variant/ardep.conf"    "${VARIANT_DIR}/${VARIANT}.conf"
cp "${ARDEP_DIR}/arduino/variant/variant.h"     "${VARIANT_DIR}/variant.h"

echo ">> Building loader for ${BOARD} (variant ${VARIANT})"
west build -p always -d "${BUILD_DIR}" -b "${BOARD}" loader -t llext-edk -- \
	-DZEPHYR_EXTRA_MODULES="${EM}" -DBOARD_ROOT="${ARDEP_DIR}"

echo ">> Extracting LLEXT EDK into variant"
( cd "${BUILD_DIR}" && rm -rf llext-edk && tar xf zephyr/llext-edk.tar.Z )
rsync -a --delete "${BUILD_DIR}/llext-edk" "${VARIANT_DIR}/"

echo ">> Stripping inline comments from EDK headers (needed for token pasting)"
find "${VARIANT_DIR}/llext-edk/include/" -type f -exec \
	perl -i -pe 's/\s*\/\*.*?\*\///gs unless /^\s*#\s*(if|else|elif|endif)/ || (/^\s*\/\*/ && !/\\$/)' {} +

echo ">> Copying loader firmwares"
mkdir -p firmwares
for ext in elf bin hex; do
	[ -f "${BUILD_DIR}/zephyr/zephyr.$ext" ] && cp "${BUILD_DIR}/zephyr/zephyr.$ext" "firmwares/zephyr-${VARIANT}.$ext"
done
cp "${BUILD_DIR}/zephyr/zephyr.dts" "firmwares/zephyr-${VARIANT}.dts"
cp "${BUILD_DIR}/zephyr/.config" "firmwares/zephyr-${VARIANT}.config"

echo ">> Generating exported symbol scripts"
extra/gen_provides.py "${BUILD_DIR}/zephyr/zephyr.elf" -L > "${VARIANT_DIR}/syms-dynamic.ld"
extra/gen_provides.py "${BUILD_DIR}/zephyr/zephyr.elf" -LF \
	"+kheap_llext_heap" "+kheap__system_heap" \
	"*sketch_base_addr=_sketch_start" "*sketch_max_size=_sketch_max_size" \
	"*loader_max_size=_loader_max_size" \
	"malloc=__wrap_malloc" "free=__wrap_free" "realloc=__wrap_realloc" \
	"calloc=__wrap_calloc" "random=__wrap_random" > "${VARIANT_DIR}/syms-static.ld"

echo ">> Generating arduino cflags/includes"
cmake -P extra/gen_arduino_files.cmake "${VARIANT}"

echo ">> Done. Loader: ${BUILD_DIR}/zephyr/zephyr.bin"
