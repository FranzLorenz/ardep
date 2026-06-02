/*
 * Arduino Core for Zephyr - variant header for the ARDEP board.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Legacy pin-name defines. SPI maps to the classic Arduino-R3 positions
 * (D10..D13), matching arduino_r3_connector.dtsi. SDA/SCL point at the header
 * I2C pins (D18/D19). These are convenience aliases; the authoritative pin map
 * lives in the devicetree overlay's zephyr,user node.
 */

#define SS   10
#define MOSI 11
#define MISO 12
#define SCK  13

#define SDA  18
#define SCL  19
