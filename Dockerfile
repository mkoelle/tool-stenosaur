FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PULSE_SERVER=unix:/tmp/pulse/pulse-socket \
    PULSE_RUNTIME_PATH=/tmp/pulse \
    DISPLAY=:99 \
    WEBPAGE_PORT=8000 \
    NOVNC_PORT=6080

# Google Chrome stable instead of Debian's chromium package: the latter hits a
# long-standing Chromium WebRTC bug (crbug.com/webrtc/5847) where an Opus
# bitrate-adaptation re-offer produces two payload-type-111 fmtp variants and
# Chrome rejects its own generated SDP, dropping Zoom's computer-audio session.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    dbus \
    ffmpeg \
    gnupg \
    novnc \
    pulseaudio \
    pulseaudio-utils \
    python3 \
    wget \
    x11vnc \
    xvfb \
    net-tools \
    procps \
    && wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update && apt-get install -y --no-install-recommends google-chrome-stable \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pulse/default.pa /etc/pulse/default.pa
COPY scripts /app/scripts
COPY webpage /app/webpage

RUN chmod +x /app/scripts/*.sh

EXPOSE 6080 5900 8000

ENTRYPOINT ["/app/scripts/entrypoint.sh"]
