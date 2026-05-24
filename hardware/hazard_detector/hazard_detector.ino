#include <HAZARDDETECOTR_FINAL_inferencing.h>






/*
 * NexusGen – Arduino Uno R4 WiFi              v3.0
 * ══════════════════════════════════════════════════
 * Hardware
 *   Microphone (MAX9814 or similar)  → A1   (DC offset ≈ 270)
 *   Servo (haptic feedback)          → D6
 *   RGB LED, common-cathode          → R:D9  G:D10  B:D11
 *   LCD 16×2, I2C addr 0x27         → SDA/SCL
 *
 * WiFi — HTTP server on port 8080
 *   GET /status  →  {"alert":"noise","confidence":0.99}
 *   alert values : "alarm" | "name" | "noise"
 *
 * Required libraries (install via Library Manager):
 *   • ei_hazarddetecotr_final_inferencing  (Edge Impulse — exported Arduino lib)
 *   • LiquidCrystal_I2C  (Frank de Brabander)
 *   • Servo               (built-in)
 *   • WiFiS3              (bundled with Arduino UNO R4 board package)
 *
 * v3.0 changes vs v2.1
 *   • Replaced amplitude-threshold classifier with TinyML (Edge Impulse EON).
 *   • Audio is sampled at 8 kHz into a 500 ms ring buffer; inference runs
 *     every buffer fill (~500 ms), latency ~1 ms per the EON benchmark.
 *   • CONFIRM_WINDOWS kept for name (2 consecutive 500 ms windows = 1 s
 *     sustained) to guard against transient false positives.
 *   • Alarm still fires on the first confirmed window — it's urgent.
 */

// ── Edge Impulse ML library ───────────────────────────────────────────────────
// If this #include fails: Arduino IDE → File → Examples → scroll to the
// Edge Impulse library → open any example to see the exact header name.

#include <WiFiS3.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <Servo.h>

// ══════════════════════════════════════════════════════════════════════════════
//  USER CONFIG — edit these before uploading
// ══════════════════════════════════════════════════════════════════════════════

const char* WIFI_SSID     = "HraklisiPhone";
const char* WIFI_PASSWORD = "trougoner";
const int   HTTP_PORT     = 8080;

// Minimum ML confidence to accept a detection (0.0 – 1.0).
// Predictions below this score are treated as noise.
const float CONF_THRESHOLD = 0.97f;

// Consecutive 500 ms inference windows that must agree on the same label
// before it triggers.  Alarm needs only 1 (urgent); name needs 2 (1 s sustained).
const uint8_t CONFIRM_ALARM = 1;
const uint8_t CONFIRM_NAME  = 2;

// How long the alert stays on the LCD / LED before reverting to idle (ms).
const uint32_t COOLDOWN_MS = 5000UL;

// ══════════════════════════════════════════════════════════════════════════════
//  PIN MAP
// ══════════════════════════════════════════════════════════════════════════════

const uint8_t PIN_MIC   = A1;
const uint8_t PIN_SERVO =  6;   // D6 — avoids timer conflict with WiFiS3 on D3
const uint8_t PIN_LED_R =  9;
const uint8_t PIN_LED_G = 10;
const uint8_t PIN_LED_B = 11;

// ══════════════════════════════════════════════════════════════════════════════
//  PERIPHERALS
// ══════════════════════════════════════════════════════════════════════════════

LiquidCrystal_I2C lcd(0x27, 16, 2);
Servo             hapticServo;
WiFiServer        httpServer(HTTP_PORT);

// ══════════════════════════════════════════════════════════════════════════════
//  GLOBAL DETECTION STATE  (written by ML classifier, read by HTTP handler)
// ══════════════════════════════════════════════════════════════════════════════

const char* currentAlert      = "noise";
float       currentConfidence = 0.99f;

// ══════════════════════════════════════════════════════════════════════════════
//  INTERNAL STATE
// ══════════════════════════════════════════════════════════════════════════════

// ── ML audio sample buffer (8 kHz, 500 ms window) ────────────────────────────
// EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE = window_ms * freq / 1000 = 500 * 8000 / 1000 = 4000
// float[] required by numpy::signal_from_buffer (the standard EI inference path)
static float    sampleBuffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE];
static uint16_t sampleIdx    = 0;
static uint32_t lastSampleUs = 0;

// ── Detection cooldown ────────────────────────────────────────────────────────
static uint32_t lastDetectMs = 0;
static bool     inCooldown   = false;

// ── Debounce and priority tracking ───────────────────────────────────────────
static const char* prevWindowAlert = "noise";
static uint8_t     consecCount     = 0;
static uint8_t     currentPriority = 0;

// ── Non-blocking haptic state machine ─────────────────────────────────────────
enum HapticPhase : uint8_t { HAP_IDLE, HAP_ON, HAP_OFF };

static struct {
    HapticPhase phase   = HAP_IDLE;
    uint8_t     total   = 0;
    uint8_t     done    = 0;
    uint8_t     deflect = 135;
    uint16_t    onMs    = 0;
    uint16_t    offMs   = 0;
    uint32_t    nextMs  = 0;
} hap;

// ══════════════════════════════════════════════════════════════════════════════
//  FORWARD DECLARATIONS
// ══════════════════════════════════════════════════════════════════════════════

static void connectWiFi();
static void printAndShowIP();
static void handleHttpClient();
static void    runMLClassifier(uint32_t now);
static void    processDetection(const char* alert, float conf, uint32_t now);
static uint8_t alertPriority(const char* alert);
static void    applyDetection(const char* alert);
static void revertToIdle();
static void hapticStart(uint8_t count, uint16_t onMs, uint16_t offMs, uint8_t deflect = 135);
static void hapticUpdate();
static void setRGB(uint8_t r, uint8_t g, uint8_t b);
static void lcdShow(const __FlashStringHelper* l1,
                    const __FlashStringHelper* l2);
static void lcdShowIP(const char* ipStr);

// ══════════════════════════════════════════════════════════════════════════════
//  SETUP
// ══════════════════════════════════════════════════════════════════════════════

void setup() {
    Serial.begin(115200);
    while (!Serial && millis() < 3000) {}

    Serial.println(F("\n============================================="));
    Serial.println(F("  NexusGen v3.0 — Arduino Uno R4 WiFi"));
    Serial.println(F("  ML engine: Edge Impulse EON Compiler"));
    Serial.println(F("============================================="));

    // ── RGB LED — dim blue while initialising ─────────────────────────────────
    pinMode(PIN_LED_R, OUTPUT);
    pinMode(PIN_LED_G, OUTPUT);
    pinMode(PIN_LED_B, OUTPUT);
    setRGB(0, 0, 80);

    // ── Haptic servo — park at neutral then self-test ─────────────────────────
    hapticServo.attach(PIN_SERVO);
    hapticServo.write(90);
    delay(300);
    Serial.println(F("[SERVO] Self-test: sweeping to 120°..."));
    hapticServo.write(120);
    delay(400);
    hapticServo.write(90);
    delay(300);
    Serial.println(F("[SERVO] Self-test complete. If it moved → OK, if not → check wiring."));
    Serial.println(F("        Wiring: Brown→GND  Red→5V  Orange→D6"));

    // ── LCD ───────────────────────────────────────────────────────────────────
    Wire.begin();
    delay(100);
    lcd.init();
    delay(50);
    lcd.clear();
    lcd.backlight();
    lcdShow(F(" NexusGen v3.0  "), F(" Initializing.. "));

    // ── Print ML model info ───────────────────────────────────────────────────
    Serial.print(F("[ML]  DSP frame size : "));
    Serial.println(EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE);
    Serial.print(F("[ML]  Label count    : "));
    Serial.println(EI_CLASSIFIER_LABEL_COUNT);
    Serial.print(F("[ML]  Labels         : "));
    for (uint8_t i = 0; i < EI_CLASSIFIER_LABEL_COUNT; i++) {
        Serial.print(ei_classifier_inferencing_categories[i]);
        if (i < EI_CLASSIFIER_LABEL_COUNT - 1) Serial.print(F(", "));
    }
    Serial.println();

    // ── Connect to WiFi, then display IP ──────────────────────────────────────
    connectWiFi();
    printAndShowIP();

    // ── Start HTTP server ─────────────────────────────────────────────────────
    httpServer.begin();
    Serial.println(F("[HTTP] Server started."));
    Serial.println(F("[SYS]  Ready — listening for sounds.\n"));

    revertToIdle();
    lastSampleUs = micros();
}

// ══════════════════════════════════════════════════════════════════════════════
//  LOOP  — fully non-blocking
// ══════════════════════════════════════════════════════════════════════════════

void loop() {
    const uint32_t now   = millis();
    const uint32_t nowUs = micros();

    // 1. Drive haptic state machine
    hapticUpdate();

    // 2. Collect audio samples at 8 kHz (one sample every 125 μs)
    if (sampleIdx < EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE) {
        if (nowUs - lastSampleUs >= 125UL) {
            lastSampleUs             = nowUs;
            sampleBuffer[sampleIdx++] = (float)analogRead(PIN_MIC);
        }
    } else {
        // Buffer full — amplitude pre-filter before running ML.
        // If the peak-to-peak level is below THR_ACTIVE, it is definitely
        // background noise; skip the (expensive) ML call entirely.
        float bufMax = 0.0f, bufMin = 1023.0f;
        for (uint16_t i = 0; i < EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE; i++) {
            if (sampleBuffer[i] > bufMax) bufMax = sampleBuffer[i];
            if (sampleBuffer[i] < bufMin) bufMin = sampleBuffer[i];
        }
        const float level = bufMax - bufMin;
        Serial.print(F("[AMP] level=")); Serial.println(level, 1);

        if (level < 40.0f) {
            // Silence — definitely noise, skip ML entirely
            processDetection("noise", 0.99f, now);
        } else if (level >= 295.0f) {
            // Very loud sound (alarm intensity) → direct amplitude classification.
            // Alarms produce level 300-400 on this mic; voice is typically 50-200.
            // This gives instant, reliable alarm detection without waiting for ML.
            processDetection("alarm", 0.95f, now);
        } else {
            // Moderate sound (40-270) → use ML to distinguish name vs noise
            runMLClassifier(now);
        }
        sampleIdx    = 0;
        lastSampleUs = micros();
    }

    // 3. Expire cooldown → revert to idle
    if (inCooldown && (now - lastDetectMs) >= COOLDOWN_MS) {
        inCooldown      = false;
        currentPriority = 0;
        consecCount     = 0;
        prevWindowAlert = "noise";
        Serial.println(F("[SYS] Alert cleared → monitoring"));
        revertToIdle();
    }

    // 4. Handle any incoming HTTP client
    handleHttpClient();
}

// ══════════════════════════════════════════════════════════════════════════════
//  ML CLASSIFIER
// ══════════════════════════════════════════════════════════════════════════════

// Runs the Edge Impulse classifier on the current sampleBuffer.
// Called once every ~500 ms when the buffer is full.
static void runMLClassifier(uint32_t now) {
    signal_t signal;
    if (numpy::signal_from_buffer(sampleBuffer, EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE, &signal) != EIDSP_OK) {
        Serial.println(F("[ML] signal_from_buffer failed"));
        return;
    }

    ei_impulse_result_t result = { 0 };
    const EI_IMPULSE_ERROR err = run_classifier(&signal, &result, false);

    if (err != EI_IMPULSE_OK) {
        Serial.print(F("[ML] run_classifier error: "));
        Serial.println(err);
        return;
    }

    // Find the label with the highest confidence score
    const char* bestLabel = "noise";
    float       bestConf  = 0.0f;
    for (uint8_t i = 0; i < EI_CLASSIFIER_LABEL_COUNT; i++) {
        Serial.print(F("[ML] "));
        Serial.print(result.classification[i].label);
        Serial.print(F(": "));
        Serial.println(result.classification[i].value, 3);

        if (result.classification[i].value > bestConf) {
            bestConf  = result.classification[i].value;
            bestLabel = result.classification[i].label;
        }
    }

    // Reject low-confidence predictions
    if (bestConf < CONF_THRESHOLD) bestLabel = "noise";

    Serial.print(F("[ML] → best: "));
    Serial.print(bestLabel);
    Serial.print(F("  conf="));
    Serial.println(bestConf, 3);

    processDetection(bestLabel, bestConf, now);
}

// ── processDetection ──────────────────────────────────────────────────────────
// Applies debounce, priority gating and cooldown — same logic as v2.1,
// but now driven by ML labels instead of amplitude thresholds.
// ─────────────────────────────────────────────────────────────────────────────
static void processDetection(const char* alert, float conf, uint32_t now) {
    // Always update the HTTP endpoint so the app sees the current ML result
    currentAlert      = alert;
    currentConfidence = conf;

    // Noise resets the debounce streak
    if (strcmp(alert, "noise") == 0) {
        prevWindowAlert = "noise";
        consecCount     = 0;
        return;
    }

    // Debounce: accumulate consecutive matching windows
    if (strcmp(alert, prevWindowAlert) == 0) {
        consecCount++;
    } else {
        prevWindowAlert = alert;
        consecCount     = 1;
    }

    // Alarm fires on 1st window; name needs CONFIRM_NAME consecutive windows
    const uint8_t needed = (strcmp(alert, "alarm") == 0) ? CONFIRM_ALARM : CONFIRM_NAME;
    if (consecCount < needed) return;

    // Priority gate: suppress weaker alerts while one is on-screen
    const uint8_t prio = alertPriority(alert);
    if (inCooldown && prio <= currentPriority) return;

    // Confirmed + gated → fire
    Serial.print(F("[DETECT] "));
    Serial.print(alert);
    Serial.print(F("  conf="));
    Serial.println(conf, 3);

    currentPriority = prio;
    lastDetectMs    = now;
    inCooldown      = true;
    consecCount     = 0;

    applyDetection(alert);
}

// ══════════════════════════════════════════════════════════════════════════════
//  WIFI
// ══════════════════════════════════════════════════════════════════════════════

static void connectWiFi() {
    Serial.print(F("[WIFI] Connecting to \""));
    Serial.print(WIFI_SSID);
    Serial.println(F("\" ..."));
    lcdShow(F(" Connecting to  "), F("     WiFi...    "));

    WiFi.disconnect();
    delay(200);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    uint8_t dots = 0;
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print('.');
        lcd.setCursor(dots % 16, 1);
        lcd.print('.');
        if (++dots >= 40) {
            Serial.println(F("\n[WIFI] ERROR: connection failed."));
            lcdShow(F("  WiFi FAILED!  "), F("Check settings  "));
            while (true) {
                setRGB(255, 0, 0); delay(250);
                setRGB(0,   0, 0); delay(250);
            }
        }
    }
    Serial.println();

    {
        uint8_t dhcpWait = 0;
        while (WiFi.localIP() == IPAddress(0, 0, 0, 0) && dhcpWait < 30) {
            delay(100);
            dhcpWait++;
        }
        if (WiFi.localIP() == IPAddress(0, 0, 0, 0)) {
            Serial.println(F("[WIFI] WARNING: DHCP timed out — IP still 0.0.0.0"));
        }
    }

    Serial.println(F("[WIFI] Connected!"));
    setRGB(0, 60, 0);
}

static void printAndShowIP() {
    const IPAddress ip = WiFi.localIP();
    char ipStr[16];
    snprintf(ipStr, sizeof(ipStr), "%d.%d.%d.%d",
             ip[0], ip[1], ip[2], ip[3]);

    Serial.print(F("[WIFI] IP      : "));  Serial.println(ipStr);
    Serial.print(F("[WIFI] Endpoint: http://"));
    Serial.print(ipStr); Serial.print(':'); Serial.println(HTTP_PORT);
    Serial.println(F("[WIFI] Route   : GET /status"));

    lcdShowIP(ipStr);
    delay(3000);
}

// ══════════════════════════════════════════════════════════════════════════════
//  HTTP SERVER
// ══════════════════════════════════════════════════════════════════════════════

static void handleHttpClient() {
    WiFiClient client = httpServer.available();
    if (!client) return;

    const uint32_t waitDeadline = millis() + 1000UL;
    while (!client.available()) {
        if (millis() > waitDeadline) { client.stop(); return; }
    }

    char    reqBuf[48] = { 0 };
    uint8_t reqLen     = 0;
    bool    lineEnd    = false;

    while (client.available() && !lineEnd) {
        const char c = (char)client.read();
        if (c == '\n') {
            lineEnd = true;
        } else if (c != '\r' && reqLen < (uint8_t)(sizeof(reqBuf) - 1)) {
            reqBuf[reqLen++] = c;
        }
    }

    uint8_t consecNL = 0;
    const uint32_t drainDeadline = millis() + 500UL;
    while (client.available() && millis() < drainDeadline) {
        const char c = (char)client.read();
        if (c == '\n') {
            if (++consecNL >= 2) break;
        } else if (c != '\r') {
            consecNL = 0;
        }
    }

    if (strncmp(reqBuf, "GET /status", 11) == 0) {
        char body[56];
        snprintf(body, sizeof(body),
                 "{\"alert\":\"%s\",\"confidence\":%.2f}",
                 currentAlert, currentConfidence);

        client.println(F("HTTP/1.1 200 OK"));
        client.println(F("Content-Type: application/json"));
        client.println(F("Access-Control-Allow-Origin: *"));
        client.println(F("Connection: close"));
        client.println();
        client.println(body);

        Serial.print(F("[HTTP] 200  "));
        Serial.println(body);

    } else {
        client.println(F("HTTP/1.1 404 Not Found"));
        client.println(F("Content-Type: application/json"));
        client.println(F("Connection: close"));
        client.println();
        client.println(F("{\"error\":\"not found\"}"));

        Serial.print(F("[HTTP] 404  req=\""));
        Serial.print(reqBuf);
        Serial.println('"');
    }

    client.flush();
    delay(2);
    client.stop();
}

// ══════════════════════════════════════════════════════════════════════════════
//  DETECTION EFFECTS  (LED + LCD + haptic)
// ══════════════════════════════════════════════════════════════════════════════

static uint8_t alertPriority(const char* alert) {
    if (strcmp(alert, "alarm") == 0) return 2;
    if (strcmp(alert, "name")  == 0) return 1;
    return 0;
}

static void applyDetection(const char* alert) {
    if (strcmp(alert, "alarm") == 0) {
        setRGB(255, 0, 0);
        lcdShow(F("   !! ALARM !!  "), F("    EVACUATE!   "));
        hapticStart(4, 250, 120, 140);

    } else if (strcmp(alert, "name") == 0) {
        setRGB(0, 0, 255);
        lcdShow(F(" Someone Calls  "), F("   Your Name!   "));
        hapticStart(2, 150, 120, 105);
    }
}

static void revertToIdle() {
    currentAlert      = "noise";
    currentConfidence = 0.99f;
    setRGB(0, 180, 0);
    lcdShow(F("   NexusGen     "), F("  Monitoring... "));
}

// ══════════════════════════════════════════════════════════════════════════════
//  NON-BLOCKING HAPTIC STATE MACHINE
// ══════════════════════════════════════════════════════════════════════════════

static void hapticStart(uint8_t count, uint16_t onMs, uint16_t offMs, uint8_t deflect) {
    hap.total   = count;
    hap.done    = 0;
    hap.deflect = deflect;
    hap.onMs    = onMs;
    hap.offMs   = offMs;
    hap.phase   = HAP_ON;
    hap.nextMs  = millis() + onMs;
    hapticServo.write(deflect);
}

static void hapticUpdate() {
    if (hap.phase == HAP_IDLE) return;
    const uint32_t now = millis();
    if (now < hap.nextMs) return;

    if (hap.phase == HAP_ON) {
        hapticServo.write(90);
        if (++hap.done >= hap.total) {
            hap.phase = HAP_IDLE;
        } else {
            hap.phase  = HAP_OFF;
            hap.nextMs = now + hap.offMs;
        }
    } else {
        hapticServo.write(hap.deflect);
        hap.phase  = HAP_ON;
        hap.nextMs = now + hap.onMs;
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  HELPERS
// ══════════════════════════════════════════════════════════════════════════════

static void setRGB(uint8_t r, uint8_t g, uint8_t b) {
    analogWrite(PIN_LED_R, r);
    analogWrite(PIN_LED_G, g);
    analogWrite(PIN_LED_B, b);
}

static void lcdShow(const __FlashStringHelper* l1,
                    const __FlashStringHelper* l2) {
    lcd.clear();
    lcd.setCursor(0, 0); lcd.print(l1);
    lcd.setCursor(0, 1); lcd.print(l2);
}

static void lcdShowIP(const char* ipStr) {
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print(F("IP:"));
    lcd.print(ipStr);
    lcd.setCursor(0, 1);
    lcd.print(F("Port:"));
    lcd.print(HTTP_PORT);
}
