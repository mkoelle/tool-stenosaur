#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY=${DISPLAY:-:99}
export PAGE_DISPLAY=${PAGE_DISPLAY:-:98}
export WEBPAGE_PORT=${WEBPAGE_PORT:-8000}
export NOVNC_PORT=${NOVNC_PORT:-6080}
export VIDEO_PIPE=/tmp/video.y4m

mkdir -p /tmp/pulse /var/run/pulse /tmp/.X11-unix /run/dbus
chown -R pulse:pulse /tmp/pulse /var/run/pulse 2>/dev/null || true
rm -f "$VIDEO_PIPE" /tmp/pulse/pulse-socket

if [ ! -S /run/dbus/system_bus_socket ]; then
  dbus-daemon --system --fork --nopidfile || true
fi

# Start PulseAudio exactly once. Re-invoking it while already running attaches
# as a client and replays default.pa's load-module/set-default-* lines against
# the live daemon, producing duplicate ".2" sinks that confuse Zoom's device list.
su -s /bin/sh pulse -c 'export HOME=/tmp/pulse; export XDG_RUNTIME_DIR=/tmp/pulse; export PULSE_RUNTIME_PATH=/tmp/pulse; pulseaudio --daemonize --no-cpu-limit --verbose --log-target=stderr --disallow-exit --file=/etc/pulse/default.pa'

for attempt in $(seq 1 20); do
  if PULSE_SERVER=unix:/tmp/pulse/pulse-socket pactl info >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

PULSE_SERVER=unix:/tmp/pulse/pulse-socket pactl info >/dev/null 2>&1 || {
  echo "PulseAudio did not start correctly" >&2
  exit 1
}

# Headless display: renders the target page for capture only, never shown via VNC.
Xvfb "$PAGE_DISPLAY" -screen 0 1280x720x24 >/tmp/xvfb-page.log 2>&1 &

# User-facing display: hosts the Zoom join browser, exposed through VNC/noVNC.
Xvfb "$DISPLAY" -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 &
sleep 2

# Serve the local page.
python3 -m http.server "$WEBPAGE_PORT" --directory /app/webpage >/tmp/webpage.log 2>&1 &
sleep 1

# Render the target page on the headless display so we can capture it to the video pipe.
DISPLAY="$PAGE_DISPLAY" google-chrome-stable \
  --no-sandbox \
  --disable-gpu \
  --disable-dev-shm-usage \
  --user-data-dir=/tmp/page-profile \
  --window-size=1280,720 \
  --autoplay-policy=no-user-gesture-required \
  "http://127.0.0.1:${WEBPAGE_PORT}" >/tmp/page-browser.log 2>&1 &

# Create a named pipe for the fake camera stream.
mkfifo "$VIDEO_PIPE"

# Capture the headless page display and feed it to the fake camera as Y4M.
ffmpeg -y \
  -f x11grab \
  -draw_mouse 0 \
  -video_size 1280x720 \
  -framerate 15 \
  -i "${PAGE_DISPLAY}+0,0" \
  -vf "format=yuv420p" \
  -f yuv4mpegpipe "$VIDEO_PIPE" >/tmp/ffmpeg.log 2>&1 &

# Ensure the noVNC root redirects to the app rather than showing the raw directory list.
cat > /usr/share/novnc/index.html <<'HTML'
<!doctype html>
<html>
  <head>
    <meta http-equiv="refresh" content="0; url=/vnc.html?host=localhost&port=6080" />
  </head>
  <body>
    <a href="/vnc.html?host=localhost&port=6080">Open noVNC</a>
  </body>
</html>
HTML

# Expose the X session through vnc/noVNC for manual click-through and setup.
x11vnc -display "$DISPLAY" -noxdamage -nopw -listen 0.0.0.0 -rfbport 5900 >/tmp/x11vnc.log 2>&1 &
/usr/share/novnc/utils/novnc_proxy --listen "$NOVNC_PORT" --vnc localhost:5900 >/tmp/novnc.log 2>&1 &

# Build the Zoom join URL. With ZOOM_MEETING_ID set, join directly (id/password/name
# baked into the URL) instead of landing on the generic join page.
if [ -n "${ZOOM_MEETING_ID:-}" ]; then
  ZOOM_JOIN_URL=$(python3 - "$ZOOM_MEETING_ID" "${ZOOM_MEETING_PASSWORD:-}" "${ZOOM_DISPLAY_NAME:-Stenosaur}" <<'PY'
import sys, base64, urllib.parse

meeting_id, password, name = sys.argv[1], sys.argv[2], sys.argv[3]
url = "https://zoom.us/wc/join/" + urllib.parse.quote(meeting_id, safe="")
params = {}
if password:
    params["pwd"] = password
if name:
    params["uname"] = name
if params:
    url += "?" + urllib.parse.urlencode(params)
print(url)
PY
  )
else
  ZOOM_JOIN_URL="https://zoom.us/wc/join/"
fi

# Launch Zoom in a second browser with Chrome fake-media input pointed at the Y4M pipe.
# PULSE_SINK routes this browser's own playback (other participants' audio) to
# zoom_out_sink, keeping it out of vmic_sink so it can't loop back into the mic.
exec env PULSE_SINK=zoom_out_sink google-chrome-stable \
  --no-sandbox \
  --disable-gpu \
  --disable-dev-shm-usage \
  --use-fake-device-for-media-stream \
  --use-file-for-fake-video-capture="$VIDEO_PIPE" \
  --use-fake-ui-for-media-stream \
  --autoplay-policy=no-user-gesture-required \
  --user-data-dir=/tmp/zoom-profile \
  "$ZOOM_JOIN_URL"
