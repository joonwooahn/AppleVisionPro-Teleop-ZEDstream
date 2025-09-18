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

    def __init__(self, ip, record = True, max_retries = 10, retry_delay = 2): 

        # Vision Pro IP 
        self.ip = ip
        self.record = record 
        self.recording = [] 
        self.latest = None 
        self.axis_transform = YUP2ZUP
        self.max_retries = max_retries
        self.retry_delay = retry_delay
        self.connected = False
        
        print(f"Vision Pro 연결 시도 중... (IP: {self.ip})")
        self.start_streaming()

    def start_streaming(self): 
        stream_thread = Thread(target = self.stream_with_retry)
        stream_thread.daemon = True  # 메인 프로세스 종료 시 함께 종료
        stream_thread.start() 
        
        # 연결될 때까지 대기 (최대 재시도 횟수만큼)
        print("Vision Pro 연결 대기 중...")
        retry_count = 0
        while self.latest is None and retry_count < self.max_retries: 
            time.sleep(0.5)
            retry_count += 1
            
        if self.latest is not None:
            print(' == DATA IS FLOWING IN! ==')
            print('Ready to start streaming.')
        else:
            print(f"연결 실패: {self.max_retries}번 재시도 후에도 연결되지 않음")


    def stream_with_retry(self):
        """재시도 메커니즘이 포함된 스트리밍"""
        retry_count = 0
        
        while retry_count < self.max_retries:
            try:
                print(f"연결 시도 {retry_count + 1}/{self.max_retries}")
                self.stream()
                break  # 성공하면 루프 종료
                
            except Exception as e:
                retry_count += 1
                print(f"연결 실패 (시도 {retry_count}/{self.max_retries}): {e}")
                
                if retry_count < self.max_retries:
                    print(f"{self.retry_delay}초 후 재시도...")
                    time.sleep(self.retry_delay)
                else:
                    print("최대 재시도 횟수 초과. 연결을 포기합니다.")
                    self.connected = False

    def stream(self): 
        request = handtracking_pb2.HandUpdate()
        try:
            with grpc.insecure_channel(f"{self.ip}:12345") as channel:
                stub = handtracking_pb2_grpc.HandTrackingServiceStub(channel)
                responses = stub.StreamHandUpdates(request)
                
                print("gRPC 연결 성공! 데이터 스트리밍 시작...")
                self.connected = True
                
                for response in responses:
                    transformations = {
                        "left_wrist": self.axis_transform @  process_matrix(response.left_hand.wristMatrix),
                        "right_wrist": self.axis_transform @  process_matrix(response.right_hand.wristMatrix),
                        "left_fingers":   process_matrices(response.left_hand.skeleton.jointMatrices),
                        "right_fingers":  process_matrices(response.right_hand.skeleton.jointMatrices),
                        "head": rotate_head(self.axis_transform @  process_matrix(response.Head)) , 
                        "left_pinch_distance": get_pinch_distance(response.left_hand.skeleton.jointMatrices),
                        "right_pinch_distance": get_pinch_distance(response.right_hand.skeleton.jointMatrices),
                    }
                    transformations["right_wrist_roll"] = get_wrist_roll(transformations["right_wrist"])
                    transformations["left_wrist_roll"] = get_wrist_roll(transformations["left_wrist"])
                    if self.record: 
                        self.recording.append(transformations)
                    self.latest = transformations 

        except Exception as e:
            print(f"스트리밍 중 오류 발생: {e}")
            self.connected = False
            raise  # 상위 함수에서 재시도할 수 있도록 예외 재발생 

    def get_latest(self): 
        return self.latest
        
    def get_recording(self): 
        return self.recording
    
    def is_connected(self):
        """연결 상태 확인"""
        return self.connected and self.latest is not None
    
    def reconnect(self):
        """수동으로 재연결 시도"""
        print("수동 재연결 시도...")
        self.connected = False
        self.latest = None
        self.start_streaming()
    

if __name__ == "__main__": 

    streamer = VisionProStreamer(ip = '10.29.230.57')
    while True: 

        latest = streamer.get_latest()
        print(latest)