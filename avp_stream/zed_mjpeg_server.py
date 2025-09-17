import argparse
import io
import threading
import time
from http import server
from socketserver import ThreadingMixIn
from typing import Optional

import cv2


BOUNDARY = "frame"


class FrameGrabber:
    def __init__(self, device_index: int, width: int, height: int, fps: int, jpeg_quality: int = 80):
        self.device_index = device_index
        self.width = width
        self.height = height
        self.fps = fps
        self.jpeg_quality = max(1, min(100, jpeg_quality))

        self.capture: Optional[cv2.VideoCapture] = None
        self.running = False
        self.thread: Optional[threading.Thread] = None
        self.lock = threading.Lock()
        self.latest_jpeg: Optional[bytes] = None

    def start(self) -> None:
        if self.running:
            return
        self.running = True

        self.capture = cv2.VideoCapture(self.device_index)
        if not self.capture.isOpened():
            raise RuntimeError(f"Failed to open video device {self.device_index}")

        # Try to set format
        if self.width > 0:
            self.capture.set(cv2.CAP_PROP_FRAME_WIDTH, float(self.width))
        if self.height > 0:
            self.capture.set(cv2.CAP_PROP_FRAME_HEIGHT, float(self.height))
        if self.fps > 0:
            self.capture.set(cv2.CAP_PROP_FPS, float(self.fps))

        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()

    def stop(self) -> None:
        self.running = False
        if self.thread is not None:
            self.thread.join(timeout=1.0)
        if self.capture is not None:
            try:
                self.capture.release()
            except Exception:
                pass
        self.thread = None
        self.capture = None

    def _loop(self) -> None:
        frame_interval = 1.0 / max(1, self.fps)
        encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), int(self.jpeg_quality)]
        while self.running and self.capture is not None:
            ok, frame = self.capture.read()
            if not ok:
                time.sleep(0.01)
                continue

            # If the camera delivered BGR, keep it; OpenCV encodes BGR to JPEG correctly.
            ok, buf = cv2.imencode('.jpg', frame, encode_param)
            if not ok:
                continue
            jpeg_bytes = buf.tobytes()
            with self.lock:
                self.latest_jpeg = jpeg_bytes
            # Pace the loop
            time.sleep(frame_interval)

    def get_jpeg(self) -> Optional[bytes]:
        with self.lock:
            return self.latest_jpeg


class ThreadingHTTPServer(ThreadingMixIn, server.HTTPServer):
    daemon_threads = True


class MJPEGRequestHandler(server.BaseHTTPRequestHandler):
    grabber: FrameGrabber = None  # type: ignore

    def do_GET(self):  # noqa: N802 (keep BaseHTTPRequestHandler style)
        if self.path.startswith('/mjpeg'):
            self._handle_mjpeg()
            return
        if self.path.startswith('/snapshot.jpg'):
            self._handle_snapshot()
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(self._html_index().encode('utf-8'))

    def _handle_snapshot(self) -> None:
        jpeg = self.grabber.get_jpeg()
        if jpeg is None:
            self.send_error(503, 'No frame available')
            return
        self.send_response(200)
        self.send_header('Content-Type', 'image/jpeg')
        self.send_header('Content-Length', str(len(jpeg)))
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        self.end_headers()
        self.wfile.write(jpeg)

    def _handle_mjpeg(self) -> None:
        self.send_response(200)
        self.send_header('Age', '0')
        self.send_header('Cache-Control', 'no-cache, private')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Content-Type', f'multipart/x-mixed-replace; boundary=--{BOUNDARY}')
        self.end_headers()
        try:
            while True:
                jpeg = self.grabber.get_jpeg()
                if jpeg is None:
                    time.sleep(0.01)
                    continue
                buffer = io.BytesIO()
                buffer.write(f"\r\n--{BOUNDARY}\r\n".encode('ascii'))
                buffer.write(b"Content-Type: image/jpeg\r\n")
                buffer.write(f"Content-Length: {len(jpeg)}\r\n\r\n".encode('ascii'))
                buffer.write(jpeg)
                self.wfile.write(buffer.getvalue())
                # Flush per frame to keep latency low
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception:
            return

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        # Silence default logging
        return

    @staticmethod
    def _html_index() -> str:
        return (
            """
            <html><head><title>ZED MJPEG</title></head>
            <body>
                <h2>ZED MJPEG Stream</h2>
                <img src="/mjpeg" style="max-width: 100%; height: auto;"/>
            </body></html>
            """
        )


def main() -> None:
    parser = argparse.ArgumentParser(description='MJPEG server for ZED/USB camera')
    parser.add_argument('--device', type=int, default=0, help='Video device index (e.g., 0)')
    parser.add_argument('--width', type=int, default=1280, help='Capture width')
    parser.add_argument('--height', type=int, default=720, help='Capture height')
    parser.add_argument('--fps', type=int, default=15, help='Capture FPS')
    parser.add_argument('--quality', type=int, default=80, help='JPEG quality (1-100)')
    parser.add_argument('--host', type=str, default='0.0.0.0', help='Bind host')
    parser.add_argument('--port', type=int, default=8080, help='Bind port')
    args = parser.parse_args()

    grabber = FrameGrabber(
        device_index=args.device,
        width=args.width,
        height=args.height,
        fps=args.fps,
        jpeg_quality=args.quality,
    )
    grabber.start()

    MJPEGRequestHandler.grabber = grabber
    httpd = ThreadingHTTPServer((args.host, args.port), MJPEGRequestHandler)
    try:
        print(f"MJPEG server running on http://{args.host}:{args.port}  (stream at /mjpeg, snapshot at /snapshot.jpg)")
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
        grabber.stop()


if __name__ == '__main__':
    main()


