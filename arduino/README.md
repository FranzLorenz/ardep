# Arduino support for ARDEP (via Arduino Core for Zephyr)

This directory adds Arduino programming support to the ARDEP board
(STM32G474VE) on top of [Arduino Core for Zephyr][acz]. It is a fork-local
integration — upstream Arduino Core explicitly does not accept new board
targets, so this lives here.

[acz]: https://github.com/arduino/ArduinoCore-zephyr

## How "Arduino on Zephyr" works

It is not the classic single-binary Arduino build. A precompiled Zephyr
firmware — the **loader** — is flashed to the board. Sketches are compiled to
freestanding ELF objects and loaded at runtime via Zephyr **LLEXT** from a
dedicated flash partition (`user_sketch`). The loader exposes the Arduino API
(`digitalWrite`, `Serial`, …) backed by Zephyr drivers.

So bringing up ARDEP means two things:

1. A **variant** (`ardep_stm32g474xx`) — devicetree overlay mapping Arduino
   pins to STM32 pins + a Kconfig fragment. See `variant/`.
2. A built **loader firmware** for the ARDEP board.

## Hardware facts

| | |
|---|---|
| MCU | STM32G474VE — Cortex-M4F, 512 KB flash, 128 KB RAM |
| Arduino headers | already defined in `boards/mercedes/ardep/arduino_r3_connector.dtsi` |
| Onboard LED | red = PC3 (active-low), green = PA3 — `LED_BUILTIN` = red |
| Debug/flash | onboard J-Link (`JLinkExe`), also DFU/UDS, pyOCD, OpenOCD |

### Flash partition design

Stock ARDEP map (512 KB): `mcuboot 96K / slot0 192K / slot1 192K / storage 32K`.
The Arduino loader runs from **slot0**; the variant overlay repurposes the
former **slot1** region as the `user_sketch` partition (no OTA second slot in
the Arduino flow). `storage` is left untouched. A blinky-sized loader uses
~45% of slot0, so there is headroom.

## Build environment (macOS, Homebrew + venv)

The Arduino Core uses its own Zephyr fork (`arduino/zephyr` @
`zephyr-arduino-v4.2.0`) in a separate west workspace, so it does NOT share
ARDEP's own `west.yml`. ARDEP is brought in as an *extra module*.

```bash
brew install cmake ninja dtc wget

# Workspace lives at ~/code/arduino-zephyr/modules/lib (west topdir)
cd ~/code/arduino-zephyr/modules/lib
git clone https://github.com/arduino/ArduinoCore-zephyr.git   # if not present
cd ArduinoCore-zephyr
./extra/bootstrap.sh            # west update + Zephyr SDK 0.16.8 (arm-zephyr-eabi)
source venv/bin/activate
pip install cryptography        # needed by mcuboot imgtool signing

# ARDEP board pulls in three modules referenced by its own west.yml:
mkdir -p ~/code/arduino-zephyr/extra-modules && cd $_
git clone https://github.com/dragonlock2/zephyrboards.git     # virtual LIN drivers
git clone -b zephyr https://github.com/frickly-systems/iso14229.git
git clone -b v1.2.1 https://github.com/CANnectivity/cannectivity.git
```

## Building the loader

The variant files must be copied into the core tree:

```bash
cd ~/code/arduino-zephyr/modules/lib/ArduinoCore-zephyr
mkdir -p variants/ardep_stm32g474xx
cp ~/code/ardep/arduino/variant/ardep.overlay variants/ardep_stm32g474xx/ardep_stm32g474xx.overlay
cp ~/code/ardep/arduino/variant/ardep.conf    variants/ardep_stm32g474xx/ardep_stm32g474xx.conf
```

`extra/build.sh ardep` does **not** work out of the box: its variant-name
probe uses `find_package(Zephyr COMPONENTS boards)`, a lightweight mode that
does not process `board_root` from a module's `module.yml`, so the out-of-tree
ARDEP board is not found. Build directly instead (variant name is
`ardep_stm32g474xx`):

```bash
source venv/bin/activate
export ZEPHYR_BASE=~/code/arduino-zephyr/modules/lib/zephyr
EM="$HOME/code/ardep;$HOME/code/arduino-zephyr/extra-modules/zephyrboards;$HOME/code/arduino-zephyr/extra-modules/iso14229;$HOME/code/arduino-zephyr/extra-modules/cannectivity"

west build -p always -d build/ardep_stm32g474xx -b ardep loader -t llext-edk -- \
    -DZEPHYR_EXTRA_MODULES="$EM" -DBOARD_ROOT="$HOME/code/ardep"
```

The `-t llext-edk` target also produces the LLEXT EDK used to compile sketches.

## Flashing (on-board Black Magic Probe, over USB-C)

ARDEP **v2's on-board debugger is a Black Magic Probe (BMP)**, reached over the
same USB-C cable — no external probe. It enumerates as two serial ports; the
lower-numbered one is the GDB server (e.g. `/dev/cu.usbmodemXXXX1`), the higher
is the target UART. (The "Black Magic DFU" USB device is the probe's *own*
firmware updater — don't flash that.) ARDEP v1 instead uses an external SWD
probe; `flash/backup.jlink` is kept for J-Link-style probes.

The verified flow (backup → loader → sketch → reset) is scripted:

```bash
arduino/flash/flash-bmp.sh /dev/cu.usbmodemXXXX1 \
  build/ardep_stm32g474xx/zephyr/zephyr.elf \
  <sketch>/build/arduino-git.zephyr.ardep/<sketch>.ino.elf-zsk.bin
```

It reads the whole 512K flash to `~/ardep-flash-backup/backup.bin` first
(anti-brick), flashes the loader, writes the sketch to `user_sketch`
(`0x08050000`), and resets. BMP refuses raw `restore` to flash, so the sketch
`.elf-zsk.bin` is converted to ihex and programmed with GDB `load`.

> **Verified 2026-06-02 on real hardware:** loader + blink sketch flashed via
> BMP, red LED (PC3) blinks at 1 Hz.

### Upload from arduino-cli / the IDE "Upload" button

A custom `bmp` upload tool (`platform.local.txt` + `bmp-upload.sh`, installed
into the core by `build-loader.sh`) lets you upload sketches normally — pick
the BMP **GDB serial port** (the lower `/dev/cu.usbmodemXXXX1`) as the port:

```bash
arduino-cli upload -b arduino-git:zephyr:ardep -p /dev/cu.usbmodemXXXX1 <sketch>
```

In the Arduino IDE: select board "Mercedes-Benz ARDEP", select that serial port,
hit Upload. The tool converts the sketch to ihex, programs `user_sketch` via
GDB `load` over the BMP, and resets.

## Status

- [x] ARDEP board compiles + links on the Arduino Zephyr fork (v4.2.0)
- [x] `ardep_stm32g474xx` variant (overlay + conf) authored
- [x] Loader firmware builds for ARDEP
- [x] Loader flashed + verified on real hardware (via on-board BMP, USB-C)
- [x] Blink sketch compiled as LLEXT, loaded, **verified blinking (red LED, 1 Hz)**
- [x] `boards.txt` entry wired for arduino-cli (`arduino-git:zephyr:ardep`)
- [x] Peripherals: **Wire (I2C2, D18/D19), SPI (spi4, D11–13), analogRead
      (A0–A5), analogWrite/PWM (D4–D9), Serial (usart3, D0/D1)** — compile green
      and boot without fault on hardware (peripherals example blinks in 3-bursts)
- [x] **IDE/CLI auto-upload** via BMP — `arduino-cli upload` and the Arduino IDE
      "Upload" button flash the sketch to `user_sketch` and reset (verified on hw)

### Peripheral pin map

| Arduino | Pin | Peripheral |
|---|---|---|
| D0/D1 | PD9/PD8 | Serial (usart3 RX/TX) |
| D4–D7 | PD12–PD15 | analogWrite (TIM4_CH1–4) |
| D8/D9 | PC6/PC7 | analogWrite (TIM8_CH1/2) |
| D11/D12/D13 | PE6/PE5/PE2 | SPI (spi4 MOSI/MISO/SCK) |
| D18/D19 | PA8/PA9 | Wire (i2c2 SDA/SCL) |
| A0–A5 | PA1/PA7/PB0/PB13/PB14/PB12 | analogRead (adc2/3/4) |

## Next build-out (deliberately deferred)

The variant overlay maps GPIO + onboard LED + header UART/I2C/SPI. ADC is
scaffolded but not wired: on ARDEP the analog pins A0..A5 are spread across
`adc1..adc4` (see `arduino_r3_connector.dtsi`), so `analogRead` needs a
per-pin io-channel map rather than a single ADC. PWM, DAC and CAN are likewise
left for a follow-up once GPIO/serial blink is proven on hardware.
