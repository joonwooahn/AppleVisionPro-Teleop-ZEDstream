#!/usr/bin/env bash
set -euo pipefail

# Usage: ./zed_h264_server.sh [PORT]
# Default PORT=5000

PORT="${1:-5000}"

# Try /dev/video0; adjust caps as needed for your ZED. H.264 encoding via NVENC.
# For ZED SDK, you may use zed_wrapper or v4l2src depending on your setup.

PIPELINE="v4l2src device=/dev/video0 ! video/x-raw,format=YUY2,width=1280,height=720,framerate=30/1 ! \
    videoconvert ! video/x-raw,format=NV12 ! \
    nvv4l2h264enc maxperf-enable=1 iframeinterval=15 insert-sps-pps=1 bitrate=8000000 preset-level=1 control-rate=1 iframeinterval=15 ! \
    h264parse config-interval=-1 ! rtph264pay pt=96 config-interval=-1 name=pay0"

echo "Starting H.264 RTP server on UDP port ${PORT} (GStreamer)"
gst-launch-1.0 -v ${PIPELINE} udpsink host=224.1.1.1 port=${PORT} auto-multicast=true ttl-mc=1


