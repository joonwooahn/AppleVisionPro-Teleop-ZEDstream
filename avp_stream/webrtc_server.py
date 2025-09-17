import argparse
import asyncio
import json
import os
import time
from typing import Optional

import cv2
from aiohttp import web
from av import VideoFrame
from aiortc import RTCPeerConnection, RTCSessionDescription, VideoStreamTrack
from aiortc.contrib.media import MediaRelay


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
            # black frame fallback
            black = VideoFrame.from_ndarray(
                (0 * (255)).astype('uint8') if False else cv2.cvtColor(
                    cv2.resize(cv2.imread(os.devnull) if False else (255 * (cv2.UMat(1, 1, cv2.CV_8UC3).get())).get(), (16, 16)),
                    cv2.COLOR_BGR2RGB
                )
            )
            black.pts, black.time_base = self.next_timestamp()
            return black

        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        vf = VideoFrame.from_ndarray(frame, format="rgb24")
        vf.pts, vf.time_base = self.next_timestamp()
        return vf


async def index(request: web.Request) -> web.Response:
    return web.FileResponse(path=os.path.join(os.path.dirname(__file__), 'webrtc_index.html'))


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


