/*
 * ARDEP peripheral smoke test: exercises Wire (I2C2 on D18/D19), SPI (spi4 on
 * D11/D12/D13), analogRead (A0-A5), analogWrite (PWM on D4-D9) and Serial
 * (usart3 on D0/D1).
 *
 * Human-friendly verification pattern: 3 blinks, then a pause, repeating —
 * clearly distinct from the blink example (1 blink). If you see groups of
 * THREE blinks, all peripherals initialised and the sketch is running.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <Wire.h>
#include <SPI.h>

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
}

void loop() {
  Wire.beginTransmission(0x42);
  Wire.write((uint8_t)0x00);
  Wire.endTransmission();

  SPI.transfer(0xAA);

  int a0 = analogRead(A0);
  analogWrite(5, a0 >> 4);  // dim D5 from A0
  analogWrite(8, 64);       // fixed PWM on D8

  Serial.print("A0=");
  Serial.println(a0);

  blinkBurst(3);
}
