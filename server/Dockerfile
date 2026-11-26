FROM python:3.12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .

# Cloud Run sets PORT; this default is for local runs. Gunicorn binds to
# 0.0.0.0:$PORT by itself when PORT is set, so the JSON (exec) form below
# needs no shell to expand it, and gunicorn gets stop signals directly.
ENV PORT=8080

# One process, so requests for the same episode share one conversion. Threads
# mostly wait (on ffmpeg, or on another thread's conversion). Matches
# --concurrency 8.
CMD ["gunicorn", "--workers", "1", "--threads", "8", "--timeout", "0", "main:app"]
