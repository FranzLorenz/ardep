/*
 * ARDEP Arduino blink — toggles the onboard red LED (LED_BUILTIN = PC3).
 *
 * SPDX-License-Identifier: Apache-2.0
 */

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
}

void loop() {
  digitalWrite(LED_BUILTIN, HIGH);
  delay(500);
  digitalWrite(LED_BUILTIN, LOW);
  delay(500);
}
