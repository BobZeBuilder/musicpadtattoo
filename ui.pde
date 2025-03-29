import ddf.minim.*;
import controlP5.*;
import processing.serial.*;

Minim minim;
AudioPlayer sound;
AudioPlayer[] pads;
String[] padSounds = {"kick.wav", "snare.wav", "hihat.wav", "clap.wav", "dirtbeat.wav", "perc.wav"};

ControlP5 cp5;
Slider slider1, slider2;
Button playPauseButton;
Knob volumeDial;
Button[] padButtons;
boolean[] padPlaying;  // Track playing state of each pad

float volume = 0.8;
boolean isPlaying = true;
boolean isPadMode = true;  // true = PAD MODE, false = SLIDER MODE

// --- Global variables for second order tone control filters ---
BassShelfFilter2 bassShelf;
TrebleShelfFilter2 trebleShelf;

color nightBg = color(20, 20, 30);
color textColor = color(200, 200, 255);
color buttonColor = color(50, 50, 80);
color activeColor = color(100, 100, 255);

// Serial communication variables
Serial arduinoPort;
int prevPausePlay = 0;
int prevVolDown = 0;
int prevVolUp = 0;
int prevMode = 0;
int[] prevPad = new int[8];  // For 8 pad inputs from Arduino

void setup() {
  size(600, 400);
  minim = new Minim(this);
  
  // Load main sound
  sound = minim.loadFile("dirtbeat.wav");
  
  // --- Initialize second order tone controls ---
  // Bass shelf: affects frequencies below 250 Hz.
  // Treble shelf: affects frequencies above 3000 Hz (adjust cutoff as needed).
  // Starting at 0 dB gain.
  bassShelf = new BassShelfFilter2(250, 0, sound.sampleRate());
  trebleShelf = new TrebleShelfFilter2(3000, 0, sound.sampleRate());
  
  // Add filters to the main sound (order matters)
  sound.addEffect(bassShelf);
  sound.addEffect(trebleShelf);
  
  sound.loop();
  
  // Load pad sounds
  pads = new AudioPlayer[padSounds.length];
  padPlaying = new boolean[padSounds.length];
  for (int i = 0; i < padSounds.length; i++) {
    pads[i] = minim.loadFile(padSounds[i]);
    padPlaying[i] = false;
  }

  cp5 = new ControlP5(this);
  
  // --- Sliders for Bass (slider1) and Treble (slider2) ---
  slider1 = cp5.addSlider("slider1")
               .setPosition(20, 50)
               .setSize(150, 20)
               .setRange(0, 100)
               .setValue(50)  // 50 maps to 0 dB gain
               .setColorBackground(buttonColor)
               .setColorForeground(activeColor)
               .setColorActive(textColor);

  slider2 = cp5.addSlider("slider2")
               .setPosition(20, 100)
               .setSize(150, 20)
               .setRange(0, 100)
               .setValue(50)  // 50 maps to 0 dB gain
               .setColorBackground(buttonColor)
               .setColorForeground(activeColor)
               .setColorActive(textColor);
  
  // Play/Pause Button for main sound
  playPauseButton = cp5.addButton("togglePlay")
                       .setLabel("Pause")
                       .setPosition(50, 260)
                       .setSize(100, 40)
                       .setColorBackground(buttonColor)
                       .setColorForeground(activeColor)
                       .setColorActive(textColor);

  // Volume Dial for main sound volume
  volumeDial = cp5.addKnob("volume")
                  .setPosition(50, 160)
                  .setRadius(30)
                  .setRange(0, 1)
                  .setValue(volume)
                  .setColorBackground(buttonColor)
                  .setColorForeground(activeColor)
                  .setColorActive(textColor);
  
  // Sound Pad Buttons (6 pads) initially set for PAD MODE
  padButtons = new Button[6];
  String[] padLabels = {"Kick", "Snare", "Hi-Hat", "Clap", "Dirtbeat", "Perc"};
  for (int i = 0; i < 6; i++) {
    int x = 200 + (i % 3) * 100;
    int y = 300 + (i / 3) * 50;
    padButtons[i] = cp5.addButton("pad" + i)
                       .setLabel(padLabels[i])
                       .setPosition(x, y)
                       .setSize(80, 40)
                       .setColorBackground(buttonColor)
                       .setColorForeground(activeColor)
                       .setColorActive(textColor);
  }
  
  // Initialize Serial communication (choose the appropriate port if needed)
  println(Serial.list());
  // Assumes the Arduino is at index 0; adjust if necessary.
  arduinoPort = new Serial(this, Serial.list()[0], 115200);
  arduinoPort.bufferUntil('\n');
}

void draw() {
  background(nightBg);
  
  // Title and waveform
  fill(textColor);
  textSize(16);
  text("Sound Board", 250, 30);
  drawWaveform();
  
  // --- Update Tone Control Filters based on Slider Values ---
  // Map slider values (0-100) to a gain range (–12 dB to +12 dB)
  float bassGain = map(slider1.getValue(), 0, 100, -12, 12);
  float trebleGain = map(slider2.getValue(), 0, 100, -12, 12);
  bassShelf.setGain(bassGain);
  trebleShelf.setGain(trebleGain);
  
  // Apply overall volume (convert to dB range)
  float gainVal = map(volume, 0, 1, -80, 0);
  sound.setGain(gainVal);
  for (int i = 0; i < pads.length; i++) {
    pads[i].setGain(gainVal);
  }
  
  // Display current mode at bottom left
  textSize(16);
  if (isPadMode) {
    text("PAD MODE", 10, height - 10);
  } else {
    text("SLIDER MODE", 10, height - 10);
  }
}

void drawWaveform() {
  stroke(activeColor);
  noFill();
  beginShape();
  if (sound.isPlaying()) {
    for (int i = 0; i < width / 2; i++) {
      int bufferIndex = int(map(i, 0, width / 2, 0, sound.bufferSize()));
      float wave = sound.left.get(bufferIndex) * 50;
      vertex(width / 2 + i, height / 3 + wave);
    }
  }
  endShape();
}

// GUI Button Event Handlers (when buttons on screen are clicked)
void pad0() { handlePadAction(0); }
void pad1() { handlePadAction(1); }
void pad2() { handlePadAction(2); }
void pad3() { handlePadAction(3); }
void pad4() { handlePadAction(4); }
void pad5() { handlePadAction(5); }

void handlePadAction(int index) {
  // In PAD MODE, toggle the pad sound
  if (isPadMode) {
    togglePad(index);
  } else {
    // In SLIDER MODE, simulate a pad press by adjusting sliders:
    if (index == 0) { // Increase slider1 (bass)
      slider1.setValue(min(slider1.getValue() + 5, slider1.getMax()));
    } else if (index == 1) { // Decrease slider1
      slider1.setValue(max(slider1.getValue() - 5, slider1.getMin()));
    } else if (index == 2) { // Increase slider2 (treble)
      slider2.setValue(min(slider2.getValue() + 5, slider2.getMax()));
    } else if (index == 3) { // Decrease slider2
      slider2.setValue(max(slider2.getValue() - 5, slider2.getMin()));
    }
    // Pads 4 and 5 are not assigned in SLIDER MODE
  }
}

void togglePad(int index) {
  if (padPlaying[index]) {
    pads[index].pause();
  } else {
    pads[index].rewind();
    pads[index].play();
  }
  padPlaying[index] = !padPlaying[index];
}

void volume(float v) {
  volume = v;
}

// Toggle main sound play/pause
void togglePlay() {
  if (isPlaying) {
    sound.pause();
    stopAllPads();
    playPauseButton.setLabel("Play");
  } else {
    sound.loop();
    playPauseButton.setLabel("Pause");
  }
  isPlaying = !isPlaying;
}

void stopAllPads() {
  for (int i = 0; i < pads.length; i++) {
    pads[i].pause();
    padPlaying[i] = false;
  }
}

// Process incoming serial data from Arduino
void serialEvent(Serial p) {
  String data = trim(p.readStringUntil('\n'));
  // Expect a CSV line: pausePlay,volDown,volUp,mode, pad0,...,pad7
  if (data.indexOf(",") != -1) {
    String[] tokens = split(data, ",");
    if (tokens.length >= 12) {
      int arPause = int(tokens[0]);
      int arVolDown = int(tokens[1]);
      int arVolUp = int(tokens[2]);
      int arMode = int(tokens[3]);
      
      int[] arPads = new int[8];
      for (int i = 0; i < 8; i++) {
        arPads[i] = int(tokens[4 + i]);
      }
      
      // Process Pause/Play (E0)
      if (arPause == 1 && prevPausePlay == 0) {
        togglePlay();
      }
      prevPausePlay = arPause;
      
      // Process Volume Up (E2)
      if (arVolUp == 1 && prevVolUp == 0) {
        volume = min(volume + 0.1, 1);
        volumeDial.setValue(volume);
      }
      prevVolUp = arVolUp;
      
      // Process Volume Down (E1)
      if (arVolDown == 1 && prevVolDown == 0) {
        volume = max(volume - 0.1, 0);
        volumeDial.setValue(volume);
      }
      prevVolDown = arVolDown;
      
      // Process Mode toggle (E3) to switch between PAD and SLIDER modes
      if (arMode == 1 && prevMode == 0) {
        isPadMode = !isPadMode;
        // Update pad button labels based on current mode:
        if (isPadMode) {
          padButtons[0].setLabel("Kick");
          padButtons[1].setLabel("Snare");
          padButtons[2].setLabel("Hi-Hat");
          padButtons[3].setLabel("Clap");
          padButtons[4].setLabel("Dirtbeat");
          padButtons[5].setLabel("Perc");
        } else {
          padButtons[0].setLabel("S1+");
          padButtons[1].setLabel("S1-");
          padButtons[2].setLabel("S2+");
          padButtons[3].setLabel("S2-");
          padButtons[4].setLabel("NA");
          padButtons[5].setLabel("NA");
        }
      }
      prevMode = arMode;
      
      // Process Pad buttons (using electrodes E4–E9 for our six pad buttons)
      for (int i = 0; i < 6; i++) {
        if (arPads[i] == 1 && prevPad[i] == 0) {
          // If in PAD mode, toggle the pad sound; if in SLIDER mode, adjust slider values.
          handlePadAction(i);
        }
        prevPad[i] = arPads[i];
      }
      // Note: Arduino pads 6 and 7 (E10 & E11) are not used.
    }
  }
}

// 2nd order bass shelf filter (lower shelving)
// Adopted the scheme  from RBJ's Audio EQ Cookbook
// y[n] = B0*x[n] + B1*x[n-1] + B2*x[n-2] - A1*y[n-1] - A2*y[n-2]

class BassShelfFilter2 implements AudioEffect {
  float cutoff;     // cutoff freq
  float gainDB;     // gain in dB
  float sampleRate;
  
  // Normalized filter coefficients
  float B0, B1, B2, A1, A2;
  
  // State variables for left channel
  float prevXl1 = 0, prevXl2 = 0;
  float prevYl1 = 0, prevYl2 = 0;
  // State variables for right channel
  float prevXr1 = 0, prevXr2 = 0;
  float prevYr1 = 0, prevYr2 = 0;
  
  BassShelfFilter2(float cutoff, float gainDB, float sampleRate) {
    this.cutoff = cutoff;
    this.gainDB = gainDB;
    this.sampleRate = sampleRate;
    calcCoeffs();
  }
  
  public void setGain(float g) {
    this.gainDB = g;
    calcCoeffs();
  }
  
  // nalculate coefficients 
  void calcCoeffs() {
    float A = sqrt(pow(10, gainDB / 20.0));
    float w0 = TWO_PI * cutoff / sampleRate;
    float cs = cos(w0);
    float sn = sin(w0);
    float S = 1.0; // shelf slope
    float alpha = sn/2 * sqrt((A + 1/A)*(1/S - 1) + 2);
    
    float b0 = A * ((A+1) - (A-1)*cs + 2*sqrt(A)*alpha);
    float b1 = 2 * A * ((A-1) - (A+1)*cs);
    float b2 = A * ((A+1) - (A-1)*cs - 2*sqrt(A)*alpha);
    float a0 = (A+1) + (A-1)*cs + 2*sqrt(A)*alpha;
    float a1 = -2 * ((A-1) + (A+1)*cs);
    float a2 = (A+1) + (A-1)*cs - 2*sqrt(A)*alpha;
    
    // normalize coefficients by a0
    B0 = b0 / a0;
    B1 = b1 / a0;
    B2 = b2 / a0;
    A1 = a1 / a0;
    A2 = a2 / a0;
  }
  
  public void process(float[] samp) {
    for (int i = 0; i < samp.length; i++) {
      float x = samp[i];
      float y = B0*x + B1*prevXl1 + B2*prevXl2 - A1*prevYl1 - A2*prevYl2;
      prevXl2 = prevXl1;
      prevXl1 = x;
      prevYl2 = prevYl1;
      prevYl1 = y;
      samp[i] = y;
    }
  }
  
  public void process(float[] sampL, float[] sampR) {
    for (int i = 0; i < sampL.length; i++) {
      float xl = sampL[i];
      float xr = sampR[i];
      float yl = B0*xl + B1*prevXl1 + B2*prevXl2 - A1*prevYl1 - A2*prevYl2;
      float yr = B0*xr + B1*prevXr1 + B2*prevXr2 - A1*prevYr1 - A2*prevYr2;
      prevXl2 = prevXl1;
      prevXl1 = xl;
      prevYl2 = prevYl1;
      prevYl1 = yl;
      prevXr2 = prevXr1;
      prevXr1 = xr;
      prevYr2 = prevYr1;
      prevYr1 = yr;
      sampL[i] = yl;
      sampR[i] = yr;
    }
  }
}

// 2nd order treble shelf filter (high shelving), again got it from the same source
// y[n] = B0*x[n] + B1*x[n-1] + B2*x[n-2] - A1*y[n-1] - A2*y[n-2]

class TrebleShelfFilter2 implements AudioEffect {
  float cutoff;     // cutoff
  float gainDB;     // gain
  float sampleRate;
  
  // normalized filter coefficients
  float B0, B1, B2, A1, A2;
  
  // state variables for left channel
  float prevXl1 = 0, prevXl2 = 0;
  float prevYl1 = 0, prevYl2 = 0;
  // state variables for right channel
  float prevXr1 = 0, prevXr2 = 0;
  float prevYr1 = 0, prevYr2 = 0;
  
  TrebleShelfFilter2(float cutoff, float gainDB, float sampleRate) {
    this.cutoff = cutoff;
    this.gainDB = gainDB;
    this.sampleRate = sampleRate;
    calcCoeffs();
  }
  
  public void setGain(float g) {
    this.gainDB = g;
    calcCoeffs();
  }
  
  // calc coeff.
  void calcCoeffs() {
    float A = sqrt(pow(10, gainDB / 20.0));
    float w0 = TWO_PI * cutoff / sampleRate;
    float cs = cos(w0);
    float sn = sin(w0);
    float S = 1.0; // shelf slope
    float alpha = sn/2 * sqrt((A + 1/A)*(1/S - 1) + 2);
    
    float b0 = A * ((A+1) + (A-1)*cs + 2*sqrt(A)*alpha);
    float b1 = -2 * A * ((A-1) + (A+1)*cs);
    float b2 = A * ((A+1) + (A-1)*cs - 2*sqrt(A)*alpha);
    float a0 = (A+1) - (A-1)*cs + 2*sqrt(A)*alpha;
    float a1 = 2 * ((A-1) - (A+1)*cs);
    float a2 = (A+1) - (A-1)*cs - 2*sqrt(A)*alpha;
    
    // normalize coefficients by a0
    B0 = b0 / a0;
    B1 = b1 / a0;
    B2 = b2 / a0;
    A1 = a1 / a0;
    A2 = a2 / a0;
  }
  
  public void process(float[] samp) {
    for (int i = 0; i < samp.length; i++) {
      float x = samp[i];
      float y = B0*x + B1*prevXl1 + B2*prevXl2 - A1*prevYl1 - A2*prevYl2;
      prevXl2 = prevXl1;
      prevXl1 = x;
      prevYl2 = prevYl1;
      prevYl1 = y;
      samp[i] = y;
    }
  }
  
  public void process(float[] sampL, float[] sampR) {
    for (int i = 0; i < sampL.length; i++) {
      float xl = sampL[i];
      float xr = sampR[i];
      float yl = B0*xl + B1*prevXl1 + B2*prevXl2 - A1*prevYl1 - A2*prevYl2;
      float yr = B0*xr + B1*prevXr1 + B2*prevXr2 - A1*prevYr1 - A2*prevYr2;
      prevXl2 = prevXl1;
      prevXl1 = xl;
      prevYl2 = prevYl1;
      prevYl1 = yl;
      prevXr2 = prevXr1;
      prevXr1 = xr;
      prevYr2 = prevYr1;
      prevYr1 = yr;
      sampL[i] = yl;
      sampR[i] = yr;
    }
  }
}
