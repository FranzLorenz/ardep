<!--
SPDX-FileCopyrightText: Copyright (C) 2026 Frickly Systems GmbH

SPDX-License-Identifier: Apache-2.0
-->

# Arduino support for ARDEP

This directory turns the [ARDEP](../README.rst) board into an
Arduino-programmable target on top of
[Arduino Core for Zephyr](https://github.com/arduino/ArduinoCore-zephyr).
You write ordinary Arduino sketches (`setup()` / `loop()`, `digitalWrite`,
`Serial`, `Wire`, `SPI`, `analogRead`, `analogWrite`, `CAN`) and upload them
over the board's USB-C connector.

It is a self-contained add-on: nothing in the existing ARDEP firmware,
drivers, or board definition is modified. Everything lives under `arduino/`.

## Contents

- [How it works](#how-it-works)
- [What works](#what-works)
- [Pin map](#pin-map)
- [Quick start](#quick-start)
- [Flashing and uploading](#flashing-and-uploading)
- [Repository layout](#repository-layout)
- [Development workflow](#development-workflow)
- [Limitations](#limitations)
- [Contributing](#contributing)

## How it works

Arduino Core for Zephyr does **not** produce a classic standalone binary.
Instead:

1. A precompiled Zephyr firmware — the **loader** — is flashed once. It owns
   the hardware and exports the Arduino API.
2. Each **sketch** is compiled to a freestanding ELF and loaded at runtime via
   Zephyr [LLEXT](https://docs.zephyrproject.org/latest/services/llext/index.html)
   from a dedicated `user_sketch` flash partition.

So enabling Arduino on ARDEP requires two artifacts: a **board variant**
(`ardep_stm32g474xx` — a devicetree overlay + Kconfig fragment mapping Arduino
pins/peripherals to the STM32G4) and the **loader** built for it.

The variant deliberately reuses the board's own definitions: the Arduino
header pin map comes from `boards/mercedes/ardep/arduino_r3_connector.dtsi`, and
the ADC/DAC/CAN channels are the ones the board already configures.

### Flash layout

The Arduino loader runs as a standalone firmware that owns the whole 512 KB
flash, decoupled from ARDEP's automotive MCUboot + UDS/DFU scheme (it sets
`CONFIG_BOOTLOADER_MCUBOOT=n`):

| Region | Offset | Size | Purpose |
|---|---|---|---|
| `code` | `0x08000000` | 320 KB | the loader |
| `user_sketch` | `0x08050000` | 160 KB | the uploaded sketch (LLEXT) |
| `storage` | `0x08078000` | 32 KB | NVS/settings |

The loader uses ~180 KB flash (56 %) and ~123 KB RAM (94 % of 128 KB — see
[Limitations](#limitations)).

## What works

All of the following compile cleanly and were verified booting on real
hardware (STM32G474VE, on-board Black Magic Probe):

| Arduino API | Backend |
|---|---|
| GPIO — `pinMode` / `digitalRead` / `digitalWrite` | D0–D23 |
| `Serial` | usart3 (D0/D1) |
| `Wire` (I2C) | i2c2 (D18/D19) |
| `SPI` | spi4 (D11/D12/D13) |
| `analogRead` | adc2/3/4 (A0–A5) |
| `analogWrite` (PWM) | TIM4 (D4–D7), TIM8 (D8/D9) |
| `analogWrite(DAC0/DAC1, …)` | dac1 (PA4/PA5) |
| `CAN` (`#include <CAN.h>`) | can_a/can_b — on-board FDCAN + transceivers |
| Upload | `arduino-cli upload` / IDE "Upload" button via BMP |

## Pin map

| Arduino | STM32 | Peripheral |
|---|---|---|
| D0 / D1 | PD9 / PD8 | `Serial` (usart3 RX/TX) |
| D4–D7 | PD12–PD15 | `analogWrite` (TIM4_CH1–4) |
| D8 / D9 | PC6 / PC7 | `analogWrite` (TIM8_CH1/2) |
| D11 / D12 / D13 | PE6 / PE5 / PE2 | `SPI` (spi4 MOSI/MISO/SCK) |
| D18 / D19 | PA8 / PA9 | `Wire` (i2c2 SDA/SCL) |
| A0–A5 | PA1 / PA7 / PB0 / PB13 / PB14 / PB12 | `analogRead` (adc2/3/4) |
| DAC0 / DAC1 | PA4 / PA5 | `analogWrite(DAC0/DAC1, …)` (internal pads) |
| CAN | PB5/PB6 (can_a), PD0/PD1 (can_b) | `CAN` library |

`LED_BUILTIN` is the red LED (PC3); the green LED (PA3) is also exposed.

## Quick start

### 1. Prerequisites (macOS; Linux is analogous)

```bash
brew install cmake ninja dtc wget arduino-cli
```

### 2. Set up the Arduino-Zephyr workspace

Arduino Core for Zephyr uses its own Zephyr fork (`arduino/zephyr` @
`zephyr-arduino-v4.2.0`) in a dedicated west workspace — separate from ARDEP's
`west.yml`. ARDEP is brought in as an *extra module*.

```bash
# Workspace; the ArduinoCore-zephyr clone becomes the west "topdir/modules/lib"
mkdir -p ~/code/arduino-zephyr/modules/lib && cd $_
git clone https://github.com/arduino/ArduinoCore-zephyr.git
( cd ArduinoCore-zephyr && yes | ./extra/bootstrap.sh && . venv/bin/activate && pip install cryptography )

# Modules referenced by ARDEP's own west.yml (board + automotive drivers)
mkdir -p ~/code/arduino-zephyr/extra-modules && cd $_
git clone https://github.com/dragonlock2/zephyrboards.git
git clone -b zephyr https://github.com/frickly-systems/iso14229.git
git clone -b v1.2.1 https://github.com/CANnectivity/cannectivity.git

# Runtime tools for arduino-cli (toolchain, zephyr-sketch-tool, …)
arduino-cli core update-index
arduino-cli core install arduino:zephyr_main
ln -sfn ~/code/arduino-zephyr/modules/lib/ArduinoCore-zephyr \
        "$(arduino-cli config get directories.user)/hardware/arduino-git/zephyr"
```

### 3. Build the loader

`build-loader.sh` syncs the variant, builds the loader, regenerates the LLEXT
EDK (with the mandatory comment-strip), generates the symbol scripts, and
installs the BMP upload tool into the core. Run it from the core root:

```bash
cd ~/code/arduino-zephyr/modules/lib/ArduinoCore-zephyr
bash ~/code/ardep/arduino/build-loader.sh
```

> `extra/build.sh ardep` from upstream does **not** work for an out-of-tree
> board: its variant-name probe (`find_package(Zephyr COMPONENTS boards)`) does
> not process `board_root` from a module's `module.yml`. `build-loader.sh`
> passes `BOARD_ROOT` + `ZEPHYR_EXTRA_MODULES` explicitly instead.

Append the board to the core's `boards.txt` once (so arduino-cli/IDE see it):

```bash
grep -v '^#' ~/code/ardep/arduino/boards.txt.entry \
  >> ~/code/arduino-zephyr/modules/lib/ArduinoCore-zephyr/boards.txt
```

### 4. Write and upload a sketch

```bash
arduino-cli compile -b arduino-git:zephyr:ardep arduino/examples/blink
arduino-cli upload  -b arduino-git:zephyr:ardep -p /dev/cu.usbmodemXXXX1 arduino/examples/blink
```

In the Arduino IDE: board **"Mercedes-Benz ARDEP"**, port = the BMP GDB serial
port, then **Upload**.

## Flashing and uploading

ARDEP v2's on-board debugger is a **Black Magic Probe (BMP)**, reached over the
same USB-C cable — no external probe. It enumerates as two serial ports: the
lower-numbered `/dev/cu.usbmodemXXXX1` is the **GDB server** (use this), the
higher one is the target UART. (The "Black Magic DFU" USB device is the probe's
own firmware updater — leave it alone.)

- **First-time loader flash** (with a full-flash anti-brick backup):

  ```bash
  arduino/flash/flash-bmp.sh /dev/cu.usbmodemXXXX1 \
    build/ardep_stm32g474xx/zephyr/zephyr.elf \
    arduino/examples/blink/build/arduino-git.zephyr.ardep/blink.ino.elf-zsk.bin
  ```

  It dumps the original 512 KB to `~/ardep-flash-backup/backup.bin` first, then
  flashes the loader and the sketch and resets.

- **Subsequent sketch uploads** use the normal `arduino-cli upload` / IDE
  button (the custom `bmp` tool from `platform.local.txt` + `bmp-upload.sh`).

Because BMP refuses raw `restore` to flash, sketches are converted to ihex at
`0x08050000` and programmed with GDB `load`.

> ARDEP v1 boards use an external SWD probe instead; `flash/backup.jlink` is
> kept for J-Link-style probes.

## Repository layout

```
arduino/
├── variant/
│   ├── ardep.overlay     # devicetree: pin map, peripherals, flash layout
│   ├── ardep.conf        # Kconfig fragment for the loader
│   └── variant.h         # legacy pin-name defines (SS/MOSI/.../SDA/SCL)
├── boards.txt.entry      # board definition to append to the core's boards.txt
├── platform.local.txt    # custom "bmp" upload tool for arduino-cli/IDE
├── flash/
│   ├── flash-bmp.sh       # backup → loader → sketch → reset (BMP/GDB)
│   ├── bmp-upload.sh      # sketch upload helper used by the bmp tool
│   └── backup.jlink       # J-Link backup script (v1 / external probe)
├── examples/
│   ├── blink/             # 1-blink burst
│   └── peripherals/       # 3-blink burst, exercises every peripheral
├── build-loader.sh       # build the loader + install variant/upload files
└── test.sh               # red-green: build loader + compile examples + lint
```

## Development workflow

The "test suite" is a reproducible build. Before committing, run the
red-green gate (it builds the loader and compiles both examples, plus lint):

```bash
arduino/test.sh        # GREEN = everything builds
```

CI (`.github/workflows/arduino.yml`) runs a fast lint job on every push and the
full loader-build + example-compile as the deeper test.

**Note:** changing `variant/ardep.overlay` requires rebuilding the loader (it
regenerates the EDK) before sketches see the change — `build-loader.sh` and
`test.sh` handle that.

The example sketches use a human-readable verification convention: the LED
blinks in **bursts whose count identifies the sketch** (blink = 1, peripherals
= 3), so you can tell at a glance which sketch is running.

## Limitations

- **Beta.** Arduino Core for Zephyr is young; expect rough edges.
- **RAM is tight.** The loader uses ~94 % of the 128 KB SRAM; large sketches or
  RAM-hungry libraries may not fit. Trim the loader (`HEAP_MEM_POOL_SIZE`,
  stacks, unused subsystems) if needed.
- **Library compatibility.** Only libraries written against the Arduino API and
  compilable for the `zephyr` architecture work. Libraries that poke AVR/STM32
  registers directly will not.
- **DAC pins are internal.** PA4/PA5 are not on the Arduino header.
- **Upload port.** Pick the BMP GDB serial port (the lower `usbmodem`); there is
  no VID/PID auto-match yet, so the IDE will not pre-select it.

## Contributing

This lives in a fork of [mercedes-benz/ardep](https://github.com/mercedes-benz/ardep);
upstream Arduino Core explicitly does not accept new board targets, which is
why the variant ships here rather than in the core. Contributions follow the
repository's [CONTRIBUTING](../CONTRIBUTING.md) guidelines (CLA + pull requests).
All files carry SPDX headers (`Apache-2.0`).
