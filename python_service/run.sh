#!/usr/bin/env bash
# Starts the VocalPolish Studio DSP service. First run creates a venv and installs dependencies.
set -euo pipefail
cd "$(dirname "$0")"
[ -d .venv ] || python3 -m venv .venv
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r requirements.txt
HOST="${VP_HOST:-127.0.0.1}"   # use VP_HOST=0.0.0.0 to serve a phone over Wi-Fi
PORT="${VP_PORT:-8088}"
echo "VocalPolish DSP on http://$HOST:$PORT  (USB phone: adb reverse tcp:$PORT tcp:$PORT)"
exec .venv/bin/python -m uvicorn app.main:app --host "$HOST" --port "$PORT"
