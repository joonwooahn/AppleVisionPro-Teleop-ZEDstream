#!/usr/bin/env bash
set -euo pipefail

# Usage: ./zed_h264_tcp_server.sh [PORT]
# Default PORT=5000

PORT="${1:-5000}"

# H.264 Annex B bytestream over TCP (low-latency). Client parses start codes.

PIPELINE="v4l2src device=/dev/video0 ! video/x-raw,width=640,height=480,framerate=15/1 ! \
    videoconvert ! x264enc bitrate=2000 tune=zerolatency ! \
    h264parse ! video/x-h264,stream-format=byte-stream ! \
    tcpserversink host=0.0.0.0 port=${PORT}"

echo "Starting H.264 TCP server on port ${PORT} (Annex B bytestream)"
gst-launch-1.0 -v ${PIPELINE}


