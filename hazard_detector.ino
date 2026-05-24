/*
 * hazard_detector.ino
 * Wearable hazard detector for deaf / hard-of-hearing users.
 *
 * Hardware
 *   Microphone MAX9814  → A1          (DC offset ≈ 270)
 *   Servo (haptic sim)  → D3
 *   RGB LED CC          → R:D9  G:D10  B:D11
 *   LCD 16×2 I2C 0x27  → SDA/SCL
 *
 * Edge Impulse model: hazarddetector_inferencing
 *   Labels (alphabetical): alarm(0)  erica(1)  noise(2)  phone(3)
 *   RAW_SAMPLE_COUNT = 2000 | FREQUENCY = 8000 Hz | window = 250 ms
 */

#include <hazarddetector_inferencing.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <Servo.h>

// ── Compile-time model validation ────────────────────────────────────────────
static_assert(EI_CLASSIFIER_RAW_SAMPLE_COUNT == 2000,
              "EI model must use 2000 raw samples per window");
static_assert(EI_CLASSIFIER_FREQUENCY == 8000,
              "EI model must be trained at 8 kHz");

// ── Pin map ──────────────────────────────────────────────────────────────────
static const uint8_t PIN_MIC   = A1;
static const uint8_t PIN_SERVO = 3;
static const uint8_t PIN_LED_R = 9;
static const uint8_t PIN_LED_G = 10;
static const uint8_t PIN_LED_B = 11;

// ── Audio constants ───────────────────────────────────────────────────────────
static const uint16_t DC_OFFSET      = 270;
// Exact microseconds per sample — integer avoids float in the hot path
static const uint32_t SAMPLE_INTV_US = 1000000UL / EI_CLASSIFIER_FREQUENCY; // 125 µs

// ── Detection policy ─────────────────────────────────────────────────────────
static const float    CONF_THRESHOLD = 0.70f;
static const uint32_t COOLDOWN_MS    = 2000UL;

// ── Label indices — must match Edge Impulse alphabetical ordering ─────────────
enum Label : uint8_t {
    LBL_ALARM = 0,
    LBL_ERICA = 1,
    LBL_NOISE = 2,
    LBL_PHONE = 3
};

// Used only for Serial debug output; avoids depending on EI SDK internals.
static const char *const LABEL_NAMES[4] = { "alarm", "erica", "noise", "phone" };

// ── Peripherals ───────────────────────────────────────────────────────────────
static LiquidCrystal_I2C lcd(0x27, 16, 2);
static Servo              haptic;

// ── Circular audio buffer ─────────────────────────────────────────────────────
// int8_t = 2 KB instead of 8 KB for float. Values are decompressed on-the-fly
// inside the EI signal callback, so no second buffer is needed.
//
// Key invariant: run_inference() fires every EI_CLASSIFIER_RAW_SAMPLE_COUNT
// samples, which is exactly one full wrap of the circular buffer.  buf_head
// therefore equals 0 at every inference call, meaning audio_buf[0..1999] holds
// samples in strict chronological order — no modular offset arithmetic needed in
// the callback beyond the general formula.
static int8_t   audio_buf[EI_CLASSIFIER_RAW_SAMPLE_COUNT];
static uint16_t buf_head      = 0;   // next-write position
static bool     buf_full      = false;
static uint32_t samples_taken = 0;

// ── Timing ────────────────────────────────────────────────────────────────────
static uint32_t next_sample_us  = 0;
static uint32_t last_trigger_ms = 0;

// 0xFF = idle; otherwise the label index currently shown on the LCD / LED.
// Avoids repeated lcd.clear() calls and LED writes when nothing has changed.
static uint8_t display_state = 0xFF;

// ── Forward declarations ──────────────────────────────────────────────────────
static int  audio_signal_get_data(size_t offset, size_t length, float *out);
static void run_inference();
static void handle_detection(uint8_t label, float conf);
static void revert_to_idle();
static void set_rgb(uint8_t r, uint8_t g, uint8_t b);
static void haptic_pulse(uint8_t count, uint16_t on_ms, uint16_t off_ms);
static void lcd_show(const __FlashStringHelper *l1, const __FlashStringHelper *l2);

// ════════════════════════════════════════════════════════════════════════════
void setup() {
    Serial.begin(115200);
    while (!Serial && millis() < 3000);  // wait for USB CDC, skip after 3 s
    Serial.println(F("[HAZARD] Wearable Hazard Detector v1.0"));

    // RGB LED ─────────────────────────────────────────────────────────────────
    pinMode(PIN_LED_R, OUTPUT);
    pinMode(PIN_LED_G, OUTPUT);
    pinMode(PIN_LED_B, OUTPUT);
    set_rgb(0, 0, 128);   // dim blue = initialising

    // Haptic servo ────────────────────────────────────────────────────────────
    haptic.attach(PIN_SERVO);
    haptic.write(90);     // neutral / resting position

    // LCD ─────────────────────────────────────────────────────────────────────
    lcd.init();
    lcd.backlight();
    lcd_show(F("Hazard Detector"), F("Initializing..."));

    // Model info ──────────────────────────────────────────────────────────────
    Serial.print(F("[INFO] Labels  : ")); Serial.println(EI_CLASSIFIER_LABEL_COUNT);
    Serial.print(F("[INFO] Samples : ")); Serial.println(EI_CLASSIFIER_RAW_SAMPLE_COUNT);
    Serial.print(F("[INFO] Freq Hz : ")); Serial.println(EI_CLASSIFIER_FREQUENCY);
    Serial.print(F("[INFO] Intv µs : ")); Serial.println(SAMPLE_INTV_US);
    Serial.print(F("[INFO] Thresh  : ")); Serial.println(CONF_THRESHOLD, 2);

    next_sample_us = micros();

    revert_to_idle();
    Serial.println(F("[HAZARD] System ready — listening."));
}

// ════════════════════════════════════════════════════════════════════════════
void loop() {
    // Non-blocking audio sampler.
    // Cast to int32_t so the subtraction handles the 32-bit micros() rollover
    // correctly (the comparison flips sign cleanly at the overflow boundary).
    if ((int32_t)(micros() - next_sample_us) >= 0) {
        next_sample_us += SAMPLE_INTV_US;  // advance by fixed step — no drift

        // DC-correct, ×2 scale, clamp → int8
        // (raw - 270) * 2  maps the ~±200-count mic swing to fill ±127.
        int16_t raw = (int16_t)analogRead(PIN_MIC);
        int16_t val = (raw - (int16_t)DC_OFFSET) * 2;
        if (val >  127) val =  127;
        if (val < -128) val = -128;
        audio_buf[buf_head] = (int8_t)val;

        if (++buf_head >= (uint16_t)EI_CLASSIFIER_RAW_SAMPLE_COUNT) {
            buf_head = 0;
            buf_full = true;
        }

        // Fire inference once per 250 ms window (every 2000 samples)
        if (++samples_taken >= (uint32_t)EI_CLASSIFIER_RAW_SAMPLE_COUNT) {
            samples_taken = 0;
            run_inference();
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// Edge Impulse signal callback.
//
// Decompresses the int8 circular buffer to float in-place, element by element,
// so the DSP pipeline never needs a second 8 KB float buffer.
//
// The EI audio DSP pipeline expects raw-ADC-scale floats (≈ [-128, 127]),
// consistent with the standard int8 capture recipe: (raw - dc) >> shift.
// Here we stored (raw - 270) * 2, clamped to int8, so casting back to float
// recovers the same numeric range the model was trained on.
// ════════════════════════════════════════════════════════════════════════════
static int audio_signal_get_data(size_t offset, size_t length, float *out) {
    const uint16_t n = (uint16_t)EI_CLASSIFIER_RAW_SAMPLE_COUNT;
    for (size_t i = 0; i < length; i++) {
        // buf_head == 0 at inference time (see invariant note above), so
        // (buf_head + offset + i) % n simplifies to (offset + i), but the
        // full modular formula is retained for defensive correctness.
        out[i] = (float)audio_buf[(buf_head + offset + i) % n];
    }
    return EIDSP_OK;
}

// ════════════════════════════════════════════════════════════════════════════
static void run_inference() {
    if (!buf_full) return;  // first 250 ms window not yet filled

    signal_t sig;
    sig.total_length = EI_CLASSIFIER_RAW_SAMPLE_COUNT;
    sig.get_data     = &audio_signal_get_data;

    ei_impulse_result_t result;
    EI_IMPULSE_ERROR err = run_classifier(&sig, &result, false /* no debug */);

    if (err != EI_IMPULSE_OK) {
        Serial.print(F("[ERR] run_classifier: "));
        Serial.println((int)err);
        return;
    }

    // ── Print all scores ──────────────────────────────────────────────────────
    Serial.print(F("[SCORES] "));
    uint8_t best_lbl  = LBL_NOISE;
    float   best_conf = 0.0f;

    for (uint8_t i = 0; i < EI_CLASSIFIER_LABEL_COUNT; i++) {
        Serial.print(result.classification[i].label);
        Serial.print(':');
        Serial.print(result.classification[i].value, 3);
        Serial.print(F("  "));
        if (result.classification[i].value > best_conf) {
            best_conf = result.classification[i].value;
            best_lbl  = i;
        }
    }
    Serial.println();

    uint32_t now = millis();

    // ── Revert to idle when cooldown expires after a prior detection ──────────
    if (display_state != 0xFF && (now - last_trigger_ms) >= COOLDOWN_MS) {
        revert_to_idle();
    }

    // ── Gate: confidence, not-noise, cooldown ─────────────────────────────────
    bool fire = (best_conf >= CONF_THRESHOLD)
             && (best_lbl  != LBL_NOISE)
             && ((now - last_trigger_ms) >= COOLDOWN_MS);

    if (fire) {
        last_trigger_ms = now;
        display_state   = best_lbl;
        handle_detection(best_lbl, best_conf);
    }
}

// ════════════════════════════════════════════════════════════════════════════
static void handle_detection(uint8_t label, float conf) {
    Serial.print(F("[DETECT] "));
    Serial.print(LABEL_NAMES[label < 4 ? label : 3]);
    Serial.print(F(" conf="));
    Serial.println(conf, 3);

    switch (label) {

        // ── ALARM: fire + evacuation ──────────────────────────────────────────
        case LBL_ALARM:
            set_rgb(255, 0, 0);
            lcd_show(F("!! ALARM/SIREN!!"), F("EVACUATE AREA!"));
            haptic_pulse(2, 300, 150);   // strong double burst
            break;

        // ── ERICA: name called ────────────────────────────────────────────────
        // Note: "Someone Calls You" is 17 chars; LCD silently truncates to 16.
        // Change to F("Someone Calls!") (14 chars) if full text is required.
        case LBL_ERICA:
            set_rgb(0, 0, 255);
            lcd_show(F("Someone Calls You"), F("Erica!"));
            haptic_pulse(3, 100, 100);   // triple soft tap
            break;

        // ── PHONE: incoming call ──────────────────────────────────────────────
        case LBL_PHONE:
            set_rgb(255, 255, 255);      // white = all three channels driven high
            lcd_show(F("Phone Ringing!"), F("Check Your Phone"));
            haptic_pulse(2, 500, 200);   // double long pulse
            break;

        default:
            revert_to_idle();
            break;
    }
}

// ════════════════════════════════════════════════════════════════════════════
static void revert_to_idle() {
    display_state = 0xFF;
    set_rgb(0, 255, 0);
    lcd_show(F("System Active"), F("Monitoring..."));
}

// ════════════════════════════════════════════════════════════════════════════
// Helpers
// ════════════════════════════════════════════════════════════════════════════

static void set_rgb(uint8_t r, uint8_t g, uint8_t b) {
    analogWrite(PIN_LED_R, r);
    analogWrite(PIN_LED_G, g);
    analogWrite(PIN_LED_B, b);
}

// Blocking haptic sequence.
// Intentionally synchronous: detections are cooldown-gated, so the longest
// sequence (2 × 500 ms + 200 ms gap = 1.2 s) is safe to block the loop.
// Audio sampling resumes at the next inference window after haptic completes.
static void haptic_pulse(uint8_t count, uint16_t on_ms, uint16_t off_ms) {
    for (uint8_t i = 0; i < count; i++) {
        haptic.write(135);   // deflect — creates physical impulse
        delay(on_ms);
        haptic.write(90);    // return to neutral
        if (i < (uint8_t)(count - 1)) delay(off_ms);
    }
}

// Stores strings in flash (PROGMEM) to save SRAM on the constrained R4.
static void lcd_show(const __FlashStringHelper *l1,
                     const __FlashStringHelper *l2) {
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print(l1);
    lcd.setCursor(0, 1);
    lcd.print(l2);
}
