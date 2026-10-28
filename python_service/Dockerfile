# Production Dockerfile for VocalPolish Studio AI & Admin API (Render / Cloud Run)
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8088

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libsndfile1 \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install CPU-only PyTorch + Torchaudio first so image stays compact (<1.2 GB)
RUN pip install --upgrade pip && \
    pip install torch==2.2.2+cpu torchaudio==2.2.2+cpu --index-url https://download.pytorch.org/whl/cpu && \
    pip install deepfilternet

COPY requirements.txt /app/requirements.txt
RUN pip install -r /app/requirements.txt

# Pre-warm DeepFilterNet3 weights into container layer so cold starts do not download weights
RUN python -c "from df.enhance import init_df; init_df()" || true

COPY app /app/app

EXPOSE 8088

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8088} --workers 1"]
