#!/bin/bash

# Fail fast
set -Eeuo pipefail

# Don't drop core files by default
_acf="${ALLOW_CORE_FILES:-}"
if [[ "${_acf,,}" != "true" ]]; then
    ulimit -c 0
fi
unset _acf

export DISPLAY=:0

# Clear previous lockfile
rm -f /tmp/.X0-lock

# Start VNC server
Xvnc -SecurityTypes None -AlwaysShared=1 -geometry 1920x1080 :0 &

# Start noVNC server
./noVNC/utils/novnc_proxy --vnc localhost:5900 &

# Wait for Xvnc to be ready before starting openbox
until [ -S /tmp/.X11-unix/X0 ]; do sleep 0.1; done

# Start openbox
opts=()
if [ -f "$HOME/.config/openbox/rc.xml" ]; then
    opts+=(--config-file "$HOME/.config/openbox/rc.xml")
fi
openbox-session "${opts[@]}" &

# Start PulseAudio if PULSE_SERVER or ICECAST_PASSWORD is set.
#
# PULSE_SERVER: forward audio to a remote PulseAudio server over TCP.
#   On the remote machine, enable TCP access with:
#     pactl load-module module-native-protocol-tcp auth-anonymous=1
#   Then set PULSE_SERVER=tcp:<remote-host>:4713 when running this container.
#
# ICECAST_ENABLED: expose an Icecast HTTP streaming endpoint on port 8000.
#   Stream URL: http://<host>:8000/stream.mp3
#
# The fallback null-sink is always the default output; audio reaches the tunnel
# via a loopback module rather than by switching the default sink.
if [[ -n "${PULSE_SERVER:-}" || -n "${ICECAST_ENABLED:-}" ]]; then
    pulseaudio --start --exit-idle-time=-1 --log-level=notice

    # Null sink as permanent default — gives TWS a stable audio device and
    # provides the monitor source for Icecast and the tunnel loopback.
    pactl load-module module-null-sink sink_name=fallback \
        sink_properties=device.description=Fallback
    pactl set-default-sink fallback

    if [[ -n "${PULSE_SERVER:-}" ]]; then
        printf "PulseAudio: forwarding audio to %s\n" "${PULSE_SERVER}"
        (
            LOOPBACK_MODULE=
            while true; do
                if pactl list short sinks 2>/dev/null | grep -q tunnel; then
                    sleep 30
                    continue
                fi
                # Tunnel gone — drop any orphaned loopback before reconnecting
                if [[ -n "${LOOPBACK_MODULE:-}" ]]; then
                    pactl unload-module "$LOOPBACK_MODULE" 2>/dev/null || true
                    LOOPBACK_MODULE=
                fi
                printf "PulseAudio: attempting tunnel connection to %s\n" "${PULSE_SERVER}"
                if pactl load-module module-tunnel-sink server="${PULSE_SERVER}" 2>/dev/null; then
                    for i in $(seq 1 20); do
                        TUNNEL_SINK=$(pactl list short sinks 2>/dev/null | awk '/tunnel/{print $2; exit}')
                        [[ -n "$TUNNEL_SINK" ]] && break
                        sleep 0.5
                    done
                    if [[ -n "${TUNNEL_SINK:-}" ]]; then
                        LOOPBACK_MODULE=$(pactl load-module module-loopback \
                            source=fallback.monitor sink="$TUNNEL_SINK" \
                            latency_msec=200 2>/dev/null) || true
                        printf "PulseAudio: loopback to tunnel sink '%s' established\n" "$TUNNEL_SINK"
                    fi
                else
                    printf "PulseAudio: tunnel connection failed, retrying in 10s\n"
                    sleep 10
                fi
            done
        ) &
    fi

    if [[ -n "${ICECAST_ENABLED:-}" ]]; then
        printf "Icecast: starting streaming server on port 8000\n"
        mkdir -p /var/log/icecast2 /var/run/icecast2
        chown icecast2:icecast /var/log/icecast2 /var/run/icecast2
        cp /etc/icecast2/icecast.xml.tmpl /etc/icecast2/icecast.xml
        icecast2 -c /etc/icecast2/icecast.xml &

        # Stream fallback sink monitor to Icecast as MP3; restart on failure
        (
            until (echo > /dev/tcp/localhost/8000) 2>/dev/null; do sleep 0.5; done
            while true; do
                printf "Icecast: starting ffmpeg stream\n"
                parec --device=fallback.monitor --raw --latency-msec=100 \
                    | ffmpeg -loglevel warning \
                        -fflags +nobuffer \
                        -f s16le -ar 44100 -ac 2 -i pipe:0 \
                        -c:a libmp3lame -b:a 128k \
                        -flush_packets 1 \
                        -f mp3 \
                        "icecast://source:icecast@localhost:8000/stream.mp3" || true
                sleep 5
            done
        ) &
    fi
fi

# Start either TWS or IB Gateway
if [[ -z ${GATEWAY_OR_TWS:-} ]]; then
    # Start TWS by default if not specified
    GATEWAY_OR_TWS=tws
    command=
elif [[ ${GATEWAY_OR_TWS@L} = "gateway" ]]; then
    command='-g'
elif [[ ${GATEWAY_OR_TWS@L} = "tws" ]]; then
    command=
else
    printf "GATEWAY_OR_TWS must be either 'gateway' or 'tws': got '%s'\n" "$GATEWAY_OR_TWS"
    exit 1
fi

# Forward correct port with socat
if [[ ${GATEWAY_OR_TWS@L} = "gateway" ]]; then
    if [[ ${IBC_TradingMode:-live} = "live" ]]; then
        # IBGateway Live
        port=4001
    else
        # IBGateway Paper
        port=4002
    fi
elif [[ ${IBC_TradingMode:-live} = "live" ]]; then
    # TWS Live
    port=7496
else
    # TWS Paper
    port=7497
fi

printf "Listening for incoming API connections on %s\n" $port
socat -d -d TCP-LISTEN:8888,fork TCP:127.0.0.1:${port} &

# Hacky way to get the major version for IB Gateway/TWS
TWS_MAJOR_VERSION=$(ls ~/Jts/ibgateway/.)

# Override /opt/ibc/config.ini with environment variables
./replace.sh ~/ibc/config.ini

# --on2fatimeout was previously supplied by gatewaystart.sh/twsstart.sh,
# so we need to supply it here. The rest of the arguments can be read from
# the config.ini file.

exec /opt/ibc/scripts/ibcstart.sh "${TWS_MAJOR_VERSION}" $command \
    "--user=${USERNAME:-}" \
    "--pw=${PASSWORD:-}" \
    "--on2fatimeout=${TWOFA_TIMEOUT_ACTION:-restart}" \
    "--tws-settings-path=${TWS_SETTINGS_PATH:-}"
