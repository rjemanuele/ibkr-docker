# Audio Transport

TWS plays audible buy/sell notifications and alerts. This image can forward that audio out of the container in two ways:

- **PulseAudio tunnel** — stream directly to a remote PulseAudio server (low latency, LAN)
- **Icecast HTTP stream** — expose an MP3 stream on port 8000 (browser/VLC friendly)

Both can be active at the same time.

## PulseAudio Tunnel (`PULSE_SERVER`)

Forwards audio to a remote PulseAudio server over TCP.

**On the remote machine**, allow TCP connections:

```bash
pactl load-module module-native-protocol-tcp auth-anonymous=1
```

To persist across reboots, add that line to `/etc/pulse/default.pa`.

**Run the container** with `PULSE_SERVER` pointing at the remote host:

```bash
docker run -d \
  -p "127.0.0.1:6080:6080" \
  -p "127.0.0.1:8888:8888" \
  --ulimit nofile=10000 \
  -e USERNAME=your_username \
  -e PASSWORD=your_password \
  -e PULSE_SERVER=tcp:<remote-host>:4713 \
  ghcr.io/extrange/ibkr:latest
```

Or in `compose.yml`:

```yml
environment:
  PULSE_SERVER: tcp:<remote-host>:4713
```

A null sink is the permanent default output so TWS always has an audio device. Audio reaches the remote server via a loopback module, and the tunnel reconnects automatically if the remote drops and comes back.

## Icecast HTTP Stream (`ICECAST_ENABLED`)

Runs an [Icecast](https://icecast.org) server inside the container and streams audio as MP3.

**Run the container** with `ICECAST_ENABLED` set and port 8000 exposed:

```bash
docker run -d \
  -p "127.0.0.1:6080:6080" \
  -p "127.0.0.1:8888:8888" \
  -p "127.0.0.1:8000:8000" \
  --ulimit nofile=10000 \
  -e USERNAME=your_username \
  -e PASSWORD=your_password \
  -e ICECAST_ENABLED=1 \
  ghcr.io/extrange/ibkr:latest
```

Or in `compose.yml`:

```yml
services:
  ibkr:
    image: ghcr.io/extrange/ibkr
    ports:
      - "127.0.0.1:6080:6080"
      - "127.0.0.1:8888:8888"
      - "127.0.0.1:8000:8000"
    ulimits:
      nofile: 10000
    environment:
      USERNAME: ${USERNAME}
      PASSWORD: ${PASSWORD}
      ICECAST_ENABLED: 1
```

Stream URL: `http://<host>:8000/stream.mp3`

Open in a browser, VLC, or any MP3-capable player.

A "🔊 Audio" button on the noVNC page connects to the stream with minimal buffering using the MediaSource API. Click it once to start, then click again to mute/unmute.

### Query parameters

| Parameter  | Description |
|------------|-------------|
| `autoAudio` | Start the audio stream automatically on page load |
| `audioUrl`  | Override the stream URL (e.g. when behind a reverse proxy) |

Examples:

```
# Auto-start audio
http://<host>:6080/?autoAudio

# Custom stream URL
http://<host>:6080/?audioUrl=https://proxy.example.com/stream.mp3

# Both together
http://<host>:6080/?autoAudio&audioUrl=https://proxy.example.com/stream.mp3
```

## Using Both Together

When both variables are set, audio is captured from the null sink and sent to both destinations simultaneously:

```yml
environment:
  PULSE_SERVER: tcp:<remote-host>:4713
  ICECAST_ENABLED: 1
```

## Troubleshooting

If the audio button is not working, open Chrome DevTools (F12) and check:

- **Console** for JavaScript errors or failed fetch requests
- **Network tab** — look for the `stream.mp3` request; if it shows a CORS error, verify the `Access-Control-Allow-Origin` header is present in the Icecast response
- **Media tab** — shows active `MediaSource` and buffer state

You can also test the stream directly in Chrome by navigating to `http://<host>:8000/stream.mp3`.

## Environment Variables

| Variable           | Description                                                        |
|--------------------|--------------------------------------------------------------------|
| `PULSE_SERVER`     | Remote PulseAudio server, e.g. `tcp:<host>:4713`                  |
| `ICECAST_ENABLED`  | Set to any non-empty value to enable Icecast on port 8000          |
| `AUDIO_URL`        | Default stream URL for the noVNC audio button; relative URLs (e.g. `/stream.mp3`) are resolved against the page origin, useful behind a reverse proxy |
| `AUDIO_AUTO_START` | Set to any non-empty value to auto-start audio on the noVNC page   |
