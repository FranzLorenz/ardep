/*
 * ARDEP Arduino blink — onboard red LED (LED_BUILTIN = PC3).
 *
 * Human-friendly verification pattern: 1 blink, then a pause, repeating.
 * The burst count identifies the sketch (blink = 1, peripherals = 3), so you
 * can tell at a glance which sketch is running on the board.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

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
}

void loop() {
  blinkBurst(1);
}
