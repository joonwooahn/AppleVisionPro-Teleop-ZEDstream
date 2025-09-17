#!/usr/bin/env bash
set -euo pipefail

# Usage: ./zed_h264_tcp_server.sh [PORT]
# Default PORT=5000

PORT="${1:-5000}"

# H.264 Annex B bytestream over TCP (low-latency). Client parses start codes.

PIPELINE="v4l2src device=/dev/video0 ! video/x-raw,format=YUY2,width=1280,height=720,framerate=30/1 ! \
    videoconvert ! video/x-raw,format=NV12 ! \
    nvv4l2h264enc maxperf-enable=1 insert-sps-pps=1 iframeinterval=30 bitrate=6000000 control-rate=1 preset-level=1 tune=low-latency ! \
    h264parse config-interval=1 alignment=au ! video/x-h264,stream-format=byte-stream,alignment=au ! \
    tcpserversink host=0.0.0.0 port=${PORT}"

echo "Starting H.264 TCP server on port ${PORT} (Annex B bytestream)"
gst-launch-1.0 -v ${PIPELINE}


