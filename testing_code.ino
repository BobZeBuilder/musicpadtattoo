#include <Wire.h>
#include <Adafruit_MPR121.h>

// Create the MPR121 object
Adafruit_MPR121 cap = Adafruit_MPR121();

// Electrode -> Purpose mapping:
// E0: Pause/Play control
// E1: Volume Down control
// E2: Volume Up control
// E3: Mode toggle (switches between PAD MODE and SLIDER MODE)
// E4 - E11: Pad buttons (we use E4–E9 for Processing; E10 & E11 are unused)
#define E_PAUSE_PLAY 0
#define E_VOL_DOWN   1
#define E_VOL_UP     2
#define E_MODE       3

void setup() {
  Serial.begin(115200);
  Serial.println("MPR121 Test");

  if (!cap.begin(0x5A)) {
    Serial.println("MPR121 not found, check wiring!");
    while (1);
  }
  Serial.println("MPR121 found and initialized!");
}

void loop() {
  uint16_t touchedData = cap.touched();

  // Read control inputs
  int valPausePlay = (touchedData & (1 << E_PAUSE_PLAY)) ? 1 : 0;
  int valVolDown   = (touchedData & (1 << E_VOL_DOWN))   ? 1 : 0;
  int valVolUp     = (touchedData & (1 << E_VOL_UP))     ? 1 : 0;
  int valMode      = (touchedData & (1 << E_MODE))       ? 1 : 0;

  // Read pad inputs for electrodes E4 to E11
  int padVal[8];
  for (int i = 0; i < 8; i++) {
    int electrodeIndex = 4 + i;
    padVal[i] = (touchedData & (1 << electrodeIndex)) ? 1 : 0;
  }

  // Output CSV line: pausePlay,volDown,volUp,mode, pad0,...,pad7
  Serial.print(valPausePlay); Serial.print(",");
  Serial.print(valVolDown);   Serial.print(",");
  Serial.print(valVolUp);     Serial.print(",");
  Serial.print(valMode);
  for (int i = 0; i < 8; i++) {
    Serial.print(",");
    Serial.print(padVal[i]);
  }
  Serial.println();

  delay(1000); // Update interval (1 second)
}
