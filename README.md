# Stenosaur

A Dockerized browser-based Zoom prototype that exposes a local webpage as a virtual webcam feed and mixes local audio into a virtual microphone sink.

This project follows the fully-containerized browser approach from the session summary:

- a local HTML page is rendered in a headless browser on its own X display (`:98`), never shown via VNC
- ffmpeg captures that headless display through Xvfb and writes a Y4M named pipe
- a second Chrome, on the user-facing display (`:99`), uses the fake-media stream flags to read that pipe into Zoom Web
- PulseAudio creates a null sink called `vmic_sink` for the virtual microphone
- noVNC exposes only the user-facing display, so you can join the meeting and select the right devices without seeing the capture source

## What this prototype does

- Displays a local HTML page as a webcam-like video input
- Streams the page into a fake camera feed for Zoom web
- Exposes a virtual mic via PulseAudio null sink `vmic_sink`
- Lets you route additional audio into the mic via `scripts/play-audio.sh`
- Provides browser access through noVNC at port `6080`

## Prerequisites

- Docker
- Docker Compose
- A Zoom account that supports joining a meeting from the browser

No host-side kernel module or `/dev/video*` setup is required for the video path in this design.

## Build and run

This project works with either Docker or Podman. The commands below are the same conceptually; use the one that matches your local runtime.

### Docker

```bash
docker compose build
docker compose up --build
```

### Podman

```bash
podman compose build
podman compose up --build
```

If your system exposes Podman through the Docker CLI, this also works:

```bash
docker compose build
docker compose up --build
```

Then open:

- http://localhost:6080/ for the noVNC browser session (redirects to the app)
- http://localhost:6080/vnc.html?host=localhost&port=6080 for the direct noVNC page
- http://localhost:8000 for the local page preview, if you want to inspect it directly

## Join the Zoom meeting

### Auto-join with a meeting ID/password

Copy `.env.example` to `.env` (git-ignored) and set `ZOOM_MEETING_ID` (and
`ZOOM_MEETING_PASSWORD` if the meeting has one). On start, the Zoom browser
navigates straight to that meeting instead of the generic join page. You may
still need to open noVNC once to click through Zoom's own "Join Audio"/"Start
Video" prompts, since those aren't scriptable via URL.

### Manual join

1. Leave `ZOOM_MEETING_ID` unset in `.env`.
2. Open the noVNC browser in the container.
3. Navigate to Zoom in the browser session, sign in, and join the meeting.
4. In the Zoom audio/video settings, select the Chrome fake camera and the virtual microphone source from PulseAudio.
5. If needed, trigger audio by running:

```bash
# Docker

docker compose exec stenosaur /app/scripts/play-audio.sh /path/to/audio.wav

# Podman

podman compose exec stenosaur /app/scripts/play-audio.sh /path/to/audio.wav
```

## Audio mixing

The helper script sends an audio file into the `vmic_sink` device:

```bash
./scripts/play-audio.sh ./assets/demo.wav
```

This is the simplest way to inject additional audio into the meeting mix while the webcam stream is active.

## Important notes

- This is a prototype and not a polished production environment.
- Zoom Web has a different feature set from the native desktop client, so verify that the browser flow supports your required meeting features.
- Chrome fake media flags are version-sensitive; the exact command-line flags may need small adjustments depending on browser and Zoom updates.

## Repository layout

- Dockerfile — container setup
- docker-compose.yml — local orchestration
- scripts/entrypoint.sh — runtime wiring
- scripts/play-audio.sh — audio injection helper
- pulse/default.pa — PulseAudio virtual mic + Zoom-output sink setup
- .env.example — template for `ZOOM_MEETING_ID` / `ZOOM_MEETING_PASSWORD` / `ZOOM_DISPLAY_NAME`
- webpage/index.html — sample browser page to display

## Next steps

1. Validate the Chrome fake-camera flow in the container.
2. Confirm Zoom Web sees the feed as a valid camera.
3. Confirm the virtual microphone appears and can be mixed with local audio.
4. Replace the sample HTML page with your real target content.
5. Harden the browser launch and Zoom UX for your specific workflow.
