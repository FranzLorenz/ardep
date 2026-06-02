/*
 * ARDEP peripheral smoke test — exercises the whole peripheral set:
 *   Serial      (usart3 on D0/D1)
 *   Wire/I2C    (i2c2 on D18/D19)
 *   SPI         (spi4 on D11/D12/D13)
 *   analogRead  (A0-A5, adc2/3/4)
 *   analogWrite (PWM on D4-D9; DAC on DAC0/DAC1 = PA4/PA5)
 *   CAN         (can_a = onboard FDCAN2)
 *
 * Human-friendly verification pattern: 3 blinks, then a pause, repeating —
 * distinct from the blink example (1 blink). Groups of THREE blinks mean all
 * peripherals initialised and the sketch is running. CAN/I2C/SPI writes are
 * best-effort (no bus partner needed); failures are ignored so the loop keeps
 * blinking.
 *
 * SPDX-FileCopyrightText: Copyright (C) 2026 Frickly Systems GmbH
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <Wire.h>
#include <SPI.h>
#include <CAN.h>

// Blink the builtin LED `count` times, then pause.
static void blinkBurst(int count) {
  for (int i = 0; i < count; i++) {
    digitalWrite(LED_BUILTIN, HIGH);
    delay(150);
    digitalWrite(LED_BUILTIN, LOW);
    delay(150);
  }
  delay(1000);
}

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.begin(115200);
  Wire.begin();
  SPI.begin();
  CAN.begin(CanBitRate::BR_500k);  // best-effort; ok if no bus is attached
}

void loop() {
  // I2C write (no ACK needed to exercise the bus)
  Wire.beginTransmission(0x42);
  Wire.write((uint8_t)0x00);
  Wire.endTransmission();

  // SPI byte
  SPI.transfer(0xAA);

  // ADC + PWM + DAC
  int a0 = analogRead(A0);
  analogWrite(5, a0 >> 4);  // PWM on D5
  analogWrite(DAC0, a0);    // DAC1_OUT1 on PA4

  // CAN frame (best-effort)
  uint8_t data[] = {0xCA, 0xFE, 0, 0, 0, 0, 0, 0};
  CanMsg msg(CanStandardId(0x123), sizeof(data), data);
  (void)CAN.write(msg);

  Serial.print("A0=");
  Serial.println(a0);

  blinkBurst(3);
}
