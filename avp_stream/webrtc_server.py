import argparse
import asyncio
import json
import os
import time
from typing import Optional
import numpy as np

import cv2
from aiohttp import web
from av import VideoFrame
from aiortc import RTCPeerConnection, RTCSessionDescription, VideoStreamTrack
from aiortc.contrib.media import MediaRelay

# Global buffer for snapshot endpoint
latest_bgr_frame = None


class CameraTrack(VideoStreamTrack):
    def __init__(self, device_index: int, width: int, height: int, fps: int):
        super().__init__()
        self.cap = cv2.VideoCapture(device_index)
        if width:
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, float(width))
        if height:
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, float(height))
        if fps:
            self.cap.set(cv2.CAP_PROP_FPS, float(fps))
        self._fps = fps if fps > 0 else 30
        self._frame_time = 1.0 / max(1, self._fps)
        self._last_ts = time.time()

    async def recv(self) -> VideoFrame:
        # Pace to target FPS
        now = time.time()
        delay = self._frame_time - max(0.0, now - self._last_ts)
        if delay > 0:
            await asyncio.sleep(delay)
        self._last_ts = time.time()

        ok, frame = self.cap.read()
        if not ok:
            # Produce a simple black frame if capture fails
            black_rgb = np.zeros((720, 1280, 3), dtype=np.uint8)
            vf = VideoFrame.from_ndarray(black_rgb, format="rgb24")
            pts, time_base = await self.next_timestamp()
            vf.pts, vf.time_base = pts, time_base
            return vf

        # Save latest frame for snapshot handler (keep as BGR)
        global latest_bgr_frame
        latest_bgr_frame = frame.copy()

        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        vf = VideoFrame.from_ndarray(frame, format="rgb24")
        pts, time_base = await self.next_timestamp()
        vf.pts, vf.time_base = pts, time_base
        return vf


async def index(request: web.Request) -> web.Response:
    return web.FileResponse(path=os.path.join(os.path.dirname(__file__), 'webrtc_index.html'))


async def snapshot(request: web.Request) -> web.Response:
    global latest_bgr_frame
    if latest_bgr_frame is None:
        # Return tiny black jpeg initially
        blank = np.zeros((720, 1280, 3), dtype=np.uint8)
        ok, buf = cv2.imencode('.jpg', blank, [int(cv2.IMWRITE_JPEG_QUALITY), 80])
        return web.Response(body=buf.tobytes(), content_type='image/jpeg')
    ok, buf = cv2.imencode('.jpg', latest_bgr_frame, [int(cv2.IMWRITE_JPEG_QUALITY), 80])
    return web.Response(body=buf.tobytes(), content_type='image/jpeg')


async def offer(request: web.Request) -> web.Response:
    params = await request.json()
    offer = RTCSessionDescription(sdp=params["sdp"], type=params["type"])

    pc = RTCPeerConnection()
    pcs.add(pc)

    @pc.on("iceconnectionstatechange")
    async def on_ice_state_change():
        if pc.iceConnectionState in ("failed", "closed", "disconnected"):
            await pc.close()
            pcs.discard(pc)

    await pc.setRemoteDescription(offer)

    local_video = relay.subscribe(camera_track)
    pc.addTrack(local_video)

    answer = await pc.createAnswer()
    await pc.setLocalDescription(answer)
    return web.json_response({"sdp": pc.localDescription.sdp, "type": pc.localDescription.type})


async def on_shutdown(app: web.Application) -> None:
    coros = [pc.close() for pc in pcs]
    await asyncio.gather(*coros)
    pcs.clear()


def create_app(args) -> web.Application:
    global relay, camera_track, pcs
    pcs = set()
    relay = MediaRelay()
    camera_track = CameraTrack(args.device, args.width, args.height, args.fps)

    app = web.Application()
    app.on_shutdown.append(on_shutdown)
    app.router.add_get('/', index)
    app.router.add_get('/snapshot.jpg', snapshot)
    app.router.add_post('/offer', offer)
    return app


def main() -> None:
    parser = argparse.ArgumentParser(description='aiortc WebRTC server for ZED/USB camera')
    parser.add_argument('--host', type=str, default='0.0.0.0')
    parser.add_argument('--port', type=int, default=8086)
    parser.add_argument('--device', type=int, default=0)
    parser.add_argument('--width', type=int, default=1280)
    parser.add_argument('--height', type=int, default=720)
    parser.add_argument('--fps', type=int, default=30)
    args = parser.parse_args()

    app = create_app(args)
    web.run_app(app, host=args.host, port=args.port)


if __name__ == '__main__':
    main()


