#!/usr/bin/env bash

# To forward TWS audio to a remote PulseAudio server:
#   1. On the remote machine, allow TCP connections:
#        pactl load-module module-native-protocol-tcp auth-anonymous=1
#      (or use auth-ip-acl=<container-ip>/24 for stricter access)
#   2. Set PULSE_SERVER below to tcp:<remote-host>:4713
#
# Recommended remote server /etc/pulse/default.pa changes:
#   Add these to prevent audio failing after the container disconnects:
#     load-module module-always-sink
#     load-module module-rescue-streams
#   Without module-always-sink the remote server will have no default sink
#   after the container disconnects and audio will stop working until
#   PulseAudio is restarted.
#   Then restart: pulseaudio --kill && pulseaudio --start

docker run \
-p '6089:6080' \
-p '8888:8888' \
--ulimit nofile=10000 \
-e USERNAME \
-e PASSWORD \
-e GATEWAY_OR_TWS=gateway \
-e IBC_TradingMode=paper \
-e IBC_AcceptNonBrokerageAccountWarning=yes \
-e IBC_AcceptIncomingConnectionAction=accept \
-e PULSE_SERVER \
-d \
image
