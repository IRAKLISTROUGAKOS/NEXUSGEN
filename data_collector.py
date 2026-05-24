import serial
import requests
import time

# ── Configuration ──────────────────────────────────────────────────────────────
COM_PORT     = "COM4"
BAUD_RATE    = 921600
API_KEY      = "ei_8683fc4dfed624f8fb9b3873e8965b51cad4f24e0334667d"
INTERVAL_MS  = 0.125          # 8 kHz → 0.125 ms per sample
DURATION_SEC = 30             # seconds per recording session

INGESTION_URL = "https://ingestion.edgeimpulse.com/api/training/data"

# ── Collect samples from Arduino serial ────────────────────────────────────────
def collect(label, duration=DURATION_SEC):
    print(f"\n  Connecting to {COM_PORT} ...")
    try:
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=2)
    except Exception as e:
        print(f"  ERROR: Cannot open {COM_PORT} — {e}")
        return

    time.sleep(1.5)       # let Arduino settle
    ser.flushInput()

    print(f"  Recording '{label}' for {duration}s ...", end="", flush=True)
    samples = []
    start   = time.time()

    while time.time() - start < duration:
        line = ser.readline().decode("utf-8", errors="ignore").strip()
        try:
            samples.append([int(line)])
        except ValueError:
            pass

    ser.close()
    print(f" done!  ({len(samples)} samples)")

    if len(samples) < 500:
        print("  !! Very few samples — check that the Arduino data-collection sketch is running.")
        return

    upload(label, samples)

# ── Upload to Edge Impulse ingestion API ───────────────────────────────────────
def upload(label, samples):
    print(f"  Uploading to Edge Impulse ...", end="", flush=True)

    payload = {
        "protected": {
            "ver": "v1",
            "alg": "none",
            "iat": int(time.time())
        },
        "signature": "0000000000000000000000000000000000000000000000000000000000000000",
        "payload": {
            "device_type": "ARDUINO_UNO_R4_WIFI",
            "interval_ms": INTERVAL_MS,
            "sensors": [{"name": "value", "units": "/"}],
            "values": samples
        }
    }

    try:
        filename = f"{label}_{int(time.time())}.json"
        resp = requests.post(
            INGESTION_URL,
            headers={
                "x-api-key":      API_KEY,
                "x-label":        label,
                "x-file-name":    filename,
                "Content-Type":   "application/json"
            },
            json=payload,
            timeout=60
        )
        if resp.status_code == 200:
            print(f" OK!")
        else:
            print(f" FAILED ({resp.status_code}): {resp.text}")
    except Exception as e:
        print(f" ERROR: {e}")

# ── Main ───────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("=" * 54)
    print("   NexusGen — Edge Impulse Data Collector")
    print("=" * 54)
    print(f"  COM Port  : {COM_PORT}")
    print(f"  Frequency : 8000 Hz  |  Duration : {DURATION_SEC}s per label")
    print()
    print("  IMPORTANT: Make sure the Arduino is running the")
    print("  DATA COLLECTION sketch (not the main firmware)!")
    print()

    labels = [
        ("alarm", "Play an alarm sound (siren / smoke detector) near the mic"),
        ("name",  "Say the target name repeatedly near the mic"),
        ("noise", "Stay quiet / normal background noise — no alarm or name"),
    ]

    for label, instruction in labels:
        print(f"─── Label: '{label}' {'─' * (40 - len(label))}")
        print(f"  {instruction}")
        input(f"  Press ENTER when ready to record '{label}' ...")
        collect(label)
        if label != labels[-1][0]:
            print("  Waiting 3 s before next label ...")
            time.sleep(3)

    print()
    print("=" * 54)
    print("  All done! Open Edge Impulse dashboard to verify.")
    print("  Data acquisition → check that all 3 labels appear.")
    print("=" * 54)
