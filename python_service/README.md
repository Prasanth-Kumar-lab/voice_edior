# VocalPolish Studio DSP (Python)

Neural speech/vocal enhancement used by the app. If this service is unreachable the app falls back to the
native Kotlin engine on the phone, so recording and processing always work.

```bash
./run.sh                      # http://127.0.0.1:8088
adb reverse tcp:8088 tcp:8088 # phone over USB reaches it as localhost
VP_HOST=0.0.0.0 ./run.sh      # phone over Wi-Fi: set the server URL in the app to http://<mac-ip>:8088
```

`POST /enhance` (multipart `file`, `mode` = `podcast` | `vocals`) → `{job_id}`; poll `GET /status/{id}`;
fetch `GET /download/{id}` (48 kHz 16-bit WAV). `GET /health` reports the engine.

## Pipelines
**podcast** (Enhance-Speech style): HPF → DeepFilterNet3 → room-echo reduction → gap expander → adaptive studio EQ →
de-ess → leveler → compressor → **-16 LUFS**, -1 dBTP.

**vocals**: YIN pitch analysis → pitch-steered low cut / mud cut / presence / de-ess frequency / compression →
DeepFilterNet3 → voicing-aware gap expander → warmth → **-14 LUFS**, -1 dBTP. Reverb is optional (`space_db`) and off by default.
