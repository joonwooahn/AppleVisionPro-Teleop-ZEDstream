#!/usr/bin/env bash
set -euo pipefail

# Usage: ./zed_h264_tcp_server.sh [PORT]
# Default PORT=5000

PORT="${1:-5000}"

# H.264 Annex B bytestream over TCP (low-latency). Client parses start codes.

PIPELINE="v4l2src device=/dev/video0 ! video/x-raw,format=YUY2,width=4416,height=1242,framerate=15/1 ! \
    videoscale ! video/x-raw,width=1280,height=720 ! \
    videoconvert ! video/x-raw,format=I420 ! x264enc bitrate=4000 tune=zerolatency option-string=\"profile=baseline\" ! \
    h264parse ! video/x-h264,stream-format=byte-stream ! \
    tcpserversink host=0.0.0.0 port=${PORT}"

echo "Starting H.264 TCP server on port ${PORT} (Annex B bytestream)"
gst-launch-1.0 -v ${PIPELINE}


