# VocalPolish

Pick **Podcast** or **Vocals / Sing**, then **Record** or **Upload** — you get a clean, mastered take back.
For Vocals, just *pick* a **Tone** (Natural · Smooth · Warm · Bright · Deep · Radio) and a **Space** (Dry · Studio Room · Plate · Hall · Surround) — tap a different one on the result screen and it re-renders; no sliders.

| Layer | Role |
|---|---|
| **Flutter** (`lib/`) | One screen: mode → record/upload → progress → A/B preview → save/share. |
| **Python** (`python_service/`) | Premium path: DeepFilterNet3 neural noise removal + room-echo reduction, adaptive EQ, de-ess, leveling, loudness (podcast −16 LUFS / vocals −14 LUFS), true-peak limiter. Vocals mode tracks pitch (YIN) and steers the low cut, mud/presence EQ, de-ess frequency and compression to the voice. |
| **Kotlin** (`android/.../dsp`, `rt`) | Native 48 kHz recorder with live meters and clean headphone monitor, plus an on-device version of the same pipeline (two-stage spectral denoise → mode chain → BS.1770 loudness mastering) used automatically when the service is unreachable. |

## Run
```bash
flutter pub get
flutter run -d <android-device>

# Premium neural path (optional — the app falls back to on-device automatically)
cd python_service && ./run.sh
adb reverse tcp:8088 tcp:8088     # phone over USB; or VP_HOST=0.0.0.0 ./run.sh and tap the "Studio AI" chip to enter http://<mac-ip>:8088
```
Production URL: `--dart-define=PYTHON_BASE_URL=https://api.example.com`.

## Tests
```bash
cd android && ./gradlew :app:testDebugUnitTest   # DSP chain, pitch, enhancer, loudness/limiter
flutter test
cd python_service && python -m unittest discover -s tests   # pipeline: noise, loudness, pitch, tone/space presets
```
`samples/` holds before/after renders (incl. a hard case with competing talkers) from the Python pipeline.
