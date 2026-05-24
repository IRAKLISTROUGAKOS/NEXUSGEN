# NexusGen — Sound Alert Wearable for the Deaf & Hard of Hearing

A wearable system that detects environmental sounds (alarms, name calls) and delivers real-time visual and haptic alerts to the user via a Flutter Android app.

---

## How It Works

1. A **microphone (MAX9814)** on the Arduino captures audio continuously.
2. A **two-stage detection pipeline** filters the signal:
   - Amplitude check first (fast, no ML needed for silence/loud alarms)
   - **TinyML model** (Edge Impulse EON Compiler) classifies ambiguous sounds into: `alarm`, `name`, `noise`
3. The Arduino exposes a lightweight **HTTP server (port 8080)** with a `/status` endpoint.
4. The **Flutter app** polls this endpoint and triggers visual + haptic alerts on the phone.

---

## Repository Structure

```
NEXUSGEN/
│
├── hardware/
│   └── hazard_detector/
│       └── hazard_detector.ino   ← Arduino sketch (main firmware)
│
├── lib/                          ← Flutter app (Dart)
│   ├── main.dart
│   ├── models/
│   │   └── alert.dart            ← AlertType enum & AlertRecord model
│   ├── pages/
│   │   ├── home_page.dart        ← Main monitoring screen
│   │   ├── history_page.dart     ← Alert history log
│   │   └── settings_page.dart   ← IP, port, sensitivity settings
│   ├── providers/
│   │   ├── alert_provider.dart   ← Alert logic, cooldown, history
│   │   └── settings_provider.dart← Persistent user settings
│   └── services/
│       └── arduino_service.dart  ← HTTP polling service
│
├── data_collector.py             ← Script used to collect training audio for Edge Impulse
├── pubspec.yaml                  ← Flutter dependencies
└── README.md
```

---

## Hardware

| Component | Role |
|---|---|
| Arduino Uno R4 WiFi | Main microcontroller + WiFi + HTTP server |
| MAX9814 Microphone | Audio capture (analog) |
| Servo SG90 | Physical alert actuator (wristband vibration) |
| RGB LED HW-479 | Visual status indicator |
| LCD I2C 16×2 | Local display of detected sound |

---

## Key Files

### [`hardware/hazard_detector/hazard_detector.ino`](hardware/hazard_detector/hazard_detector.ino)
Arduino firmware. Handles microphone sampling, two-stage detection (amplitude threshold + TinyML), HTTP server, servo, LED and LCD.

- TinyML model: Edge Impulse EON Compiler — 3 labels (`alarm`, `name`, `noise`)
- Confidence threshold: `0.97`
- HTTP server on port `8080`, endpoint `GET /status`

### [`lib/services/arduino_service.dart`](lib/services/arduino_service.dart)
Polls the Arduino HTTP endpoint from the Flutter app.

- **Sequential polling** — next request starts only after the previous one completes
- **2000 ms timeout** per request
- **3-failure grace period** before switching to Demo Mode

### [`lib/providers/alert_provider.dart`](lib/providers/alert_provider.dart)
Manages alert state and filtering on the Flutter side.

- **8-second cooldown** — prevents re-triggering the same alert
- **Noise excluded from history** — only `alarm` and `name` are recorded
- Suppresses identical consecutive alerts

### [`data_collector.py`](data_collector.py)
Python script used to record labeled audio samples for training the Edge Impulse model. Captures audio from a microphone and saves `.wav` files organized by label.

---

## ML Model (Edge Impulse)

| Parameter | Value |
|---|---|
| Sample rate | 8.000 Hz |
| Window size | 125 ms |
| Labels | alarm, name, noise |
| Training accuracy | 100% |
| Inference time (EON) | ~1 ms |
| RAM usage | 1.4 KB |
| Flash usage | 15 KB |

---

## Flutter App

Built with Flutter for Android. Requires the Arduino to be on the same WiFi network.

**Settings (configurable in-app):**
- Arduino IP address
- Port (default: `8080`)
- Polling interval
- Confidence threshold

---

## Team

**NexusGen** — Digital Innovation & Entrepreneurship 2026  
Iraklis Strougakos · Ourania *(et al.)*
