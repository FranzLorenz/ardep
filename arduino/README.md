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

## Flashing the loader

ARDEP has an onboard J-Link:

```bash
west flash -d build/ardep_stm32g474xx --runner jlink
# or: JLinkExe -device STM32G474VE -if SWD -speed 4000
```

## Status

- [x] ARDEP board compiles + links on the Arduino Zephyr fork (v4.2.0)
- [x] `ardep_stm32g474xx` variant (overlay + conf) authored
- [x] Loader firmware builds for ARDEP
- [ ] Loader flashed + verified on real hardware
- [ ] Blink sketch compiled as LLEXT, loaded, verified blinking
- [ ] `boards.txt` entry wired for arduino-cli / IDE (see `boards.txt.entry`)
- [ ] Sketch upload path (USB CDC vs. J-Link to `user_sketch`)

## Next build-out (deliberately deferred)

The variant overlay maps GPIO + onboard LED + header UART/I2C/SPI. ADC is
scaffolded but not wired: on ARDEP the analog pins A0..A5 are spread across
`adc1..adc4` (see `arduino_r3_connector.dtsi`), so `analogRead` needs a
per-pin io-channel map rather than a single ADC. PWM, DAC and CAN are likewise
left for a follow-up once GPIO/serial blink is proven on hardware.
