import grpc
from avp_stream.grpc_msg import * 
from threading import Thread
from avp_stream.utils.grpc_utils import * 
import time 
import numpy as np 


YUP2ZUP = np.array([[[1, 0, 0, 0], 
                    [0, 0, -1, 0], 
                    [0, 1, 0, 0],
                    [0, 0, 0, 1]]], dtype = np.float64)


class VisionProStreamer:

    def __init__(self, ip, record = True): 

        # Vision Pro IP 
        self.ip = ip
        self.record = record 
        self.recording = [] 
        self.latest = None 
        self.axis_transform = YUP2ZUP
        
        print(f"Vision Pro 연결 시도 중... (IP: {self.ip})")
        self.start_streaming()

    def start_streaming(self): 
        stream_thread = Thread(target = self.stream)
        stream_thread.daemon = True  # 메인 프로세스 종료 시 함께 종료
        stream_thread.start() 
        
        # 연결 타임아웃 설정 (30초)
        timeout = 30
        start_time = time.time()
        while self.latest is None and (time.time() - start_time) < timeout:
            time.sleep(0.1)
        
        if self.latest is None:
            print(f"경고: {timeout}초 내에 Vision Pro 연결에 실패했습니다.")
            print("Vision Pro가 켜져 있고 같은 네트워크에 연결되어 있는지 확인하세요.")
        else:
            print("Vision Pro 연결 성공!") 


    def stream(self): 
        request = handtracking_pb2.HandUpdate()
        retry_count = 0
        max_retries = 5
        
        while retry_count < max_retries:
            try:
                # gRPC 연결 옵션 설정
                options = [
                    ('grpc.keepalive_time_ms', 10000),
                    ('grpc.keepalive_timeout_ms', 5000),
                    ('grpc.keepalive_permit_without_calls', True),
                    ('grpc.http2.max_pings_without_data', 0),
                    ('grpc.http2.min_time_between_pings_ms', 10000),
                    ('grpc.http2.min_ping_interval_without_data_ms', 300000)
                ]
                
                with grpc.insecure_channel(f"{self.ip}:12345", options=options) as channel:
                    stub = handtracking_pb2_grpc.HandTrackingServiceStub(channel)
                    responses = stub.StreamHandUpdates(request)
                    
                    for response in responses:
                        transformations = {
                            "left_wrist": self.axis_transform @  process_matrix(response.left_hand.wristMatrix),
                            "right_wrist": self.axis_transform @  process_matrix(response.right_hand.wristMatrix),
                            "left_fingers":   process_matrices(response.left_hand.skeleton.jointMatrices),
                            "right_fingers":  process_matrices(response.right_hand.skeleton.jointMatrices),
                            "head": rotate_head(self.axis_transform @  process_matrix(response.Head)) , 
                            "left_pinch_distance": get_pinch_distance(response.left_hand.skeleton.jointMatrices),
                            "right_pinch_distance": get_pinch_distance(response.right_hand.skeleton.jointMatrices),
                            # "rgb": response.rgb, # TODO: should figure out how to get the rgb image from vision pro 
                        }
                        transformations["right_wrist_roll"] = get_wrist_roll(transformations["right_wrist"])
                        transformations["left_wrist_roll"] = get_wrist_roll(transformations["left_wrist"])
                        if self.record: 
                            self.recording.append(transformations)
                        self.latest = transformations 
                        retry_count = 0  # 성공하면 재시도 카운트 리셋
                        
            except grpc.RpcError as e:
                print(f"gRPC 연결 오류 (시도 {retry_count + 1}/{max_retries}): {e}")
                retry_count += 1
                if retry_count < max_retries:
                    wait_time = min(2 ** retry_count, 30)  # 지수 백오프, 최대 30초
                    print(f"{wait_time}초 후 재연결 시도...")
                    time.sleep(wait_time)
                else:
                    print("최대 재시도 횟수 초과. 연결을 포기합니다.")
                    break
            except Exception as e:
                print(f"예상치 못한 오류: {e}")
                retry_count += 1
                if retry_count < max_retries:
                    time.sleep(5)
                else:
                    break 

    def get_latest(self): 
        return self.latest
        
    def get_recording(self): 
        return self.recording
    
    def is_connected(self):
        """연결 상태 확인"""
        return self.latest is not None
    
    def wait_for_connection(self, timeout=30):
        """연결이 될 때까지 대기"""
        start_time = time.time()
        while not self.is_connected() and (time.time() - start_time) < timeout:
            time.sleep(0.1)
        return self.is_connected()
    

if __name__ == "__main__": 

    streamer = VisionProStreamer(ip = '10.29.230.57')
    while True: 

        latest = streamer.get_latest()
        # latest 변수 사용 (디버그용 출력 제거)