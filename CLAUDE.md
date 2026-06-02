# Claude — ARDEP fork (Arduino support)

This is a fork of [mercedes-benz/ardep](https://github.com/mercedes-benz/ardep).
The work in this fork adds **Arduino programming support** to the ARDEP board
on top of [Arduino Core for Zephyr](https://github.com/arduino/ArduinoCore-zephyr).
Everything Arduino-specific lives under [`arduino/`](arduino/).

## Golden rules

1. **Never commit, push, or flash hardware without explicit confirmation.**
2. **Red-Green before commit:** a change is only "done" when the build/test
   script is green (see below). No green, no commit.
3. **Clockodo / upstream automotive code is not our concern here** — we only add
   the Arduino layer; don't modify ARDEP's automotive drivers unless required to
   make the board build.
4. **Never brick the board:** always read out the full flash to a backup before
   flashing, flash via the on-board debugger (USB-C) or USB-DFU, never set RDP.

## What "Arduino on ARDEP" is

Not a classic single-binary build. A precompiled Zephyr **loader** is flashed to
the board; sketches are compiled to freestanding ELF (**LLEXT**) and loaded at
runtime from the `user_sketch` flash partition. So there are two artifacts:

- the **loader** firmware (one per board), and
- the **sketch** (compiled per `.ino` against the loader's EDK).

Board facts: STM32G474VE, Cortex-M4F, 512 KB flash / 128 KB RAM, on-board J-Link
(over USB-C). Arduino R3 pin map already exists in
`boards/mercedes/ardep/arduino_r3_connector.dtsi`.

## Red-Green workflow (the test)

The "test suite" for this integration is a reproducible build. Use the helper:

```bash
arduino/test.sh         # green = loader builds + blink sketch compiles
```

It (1) builds the ARDEP loader, (2) compiles the blink sketch against it, and
(3) lints the shell + formatting. Run it before every commit. CI
(`.github/workflows/arduino.yml`) runs the same thing on push.

### One-time environment setup

See [`arduino/README.md`](arduino/README.md) for the full setup. In short:

```bash
brew install cmake ninja dtc wget arduino-cli
# Arduino-Zephyr workspace at ~/code/arduino-zephyr/modules/lib/ArduinoCore-zephyr
#   ./extra/bootstrap.sh ; pip install cryptography
# Extra modules at ~/code/arduino-zephyr/extra-modules/{zephyrboards,iso14229,cannectivity}
# arduino-cli core install arduino:zephyr_main   (runtime tools)
```

### Build the loader / compile a sketch

```bash
# From the ArduinoCore-zephyr core root:
bash ~/code/ardep/arduino/build-loader.sh                  # builds loader + EDK
arduino-cli compile -b arduino-git:zephyr:ardep <sketch>   # compiles a sketch
```

Important dependency: changing `arduino/variant/ardep.overlay` requires
**rebuilding the loader** (it regenerates the EDK) before sketches see the
change. `build-loader.sh` handles the full post-processing (EDK extract, the
mandatory comment-strip of EDK headers, symbol scripts, arduino cflags).

## Flashing (safe, USB-C only — no external probe)

The ARDEP v2 on-board debugger is reached over the **same USB-C cable**.

```bash
# 1) BACK UP first (anti-brick): read out the whole 512K
JLinkExe -device STM32G474VE -if SWD -speed 4000 -autoconnect 1 \
  -CommanderScript arduino/flash/backup.jlink     # -> backup.bin

# 2) Flash the loader (replaces ARDEP bootloader; restore from backup.bin if needed)
west flash -d build/ardep_stm32g474xx --runner jlink

# 3) Upload a sketch to user_sketch (0x08050000)
arduino-cli upload -b arduino-git:zephyr:ardep -p <port> <sketch>
```

## Current status (2026-06-02)

- ✅ ARDEP board compiles/links on the Arduino Zephyr fork (v4.2.0)
- ✅ `ardep_stm32g474xx` variant: GPIO + onboard LEDs + Serial1 (usart3 on D0/D1)
- ✅ Loader builds: 169 KB flash (32%), RAM 91% (tight — trim for big sketches)
- ✅ Blink sketch compiles end-to-end to a loadable LLEXT
- ⏳ Flash + on-hardware blink verification (pending board hookup)
- ⏳ Peripheral build-out: ADC (A0–A5 span adc1–4), PWM, I2C, SPI, CAN

## Layout

| What | Where |
|------|-------|
| Variant overlay/conf/header | `arduino/variant/` |
| Loader build script | `arduino/build-loader.sh` |
| Red-green test | `arduino/test.sh` |
| boards.txt entry (for arduino-cli) | `arduino/boards.txt.entry` |
| Integration docs | `arduino/README.md` |
| CI | `.github/workflows/arduino.yml` |
