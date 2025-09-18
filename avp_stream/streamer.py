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
        
        # 먼저 기본 연결 테스트
        if not self.test_connection():
            print(f"경고: {self.ip}:12345에 연결할 수 없습니다.")
            print("Vision Pro가 켜져 있고 같은 네트워크에 연결되어 있는지 확인하세요.")
        
        self.start_streaming()

    def start_streaming(self): 
        stream_thread = Thread(target = self.stream)
        stream_thread.daemon = True  # 메인 프로세스 종료 시 함께 종료
        stream_thread.start() 
        
        # 연결될 때까지 무한 대기 (더 자세한 피드백)
        print("Vision Pro 연결 대기 중...")
        wait_count = 0
        while self.latest is None: 
            time.sleep(0.5)
            wait_count += 1
            if wait_count % 10 == 0:  # 5초마다 상태 출력
                print(f"연결 대기 중... ({wait_count * 0.5:.1f}초 경과)")
        print("Vision Pro 연결 성공!") 


    def stream(self): 
        request = handtracking_pb2.HandUpdate()
        retry_count = 0
        max_retries = 10  # 재시도 횟수 증가
        consecutive_failures = 0
        
        while True:  # 무한 루프로 변경
            try:
                # gRPC 연결 옵션 설정
                options = [
                    ('grpc.keepalive_time_ms', 10000),
                    ('grpc.keepalive_timeout_ms', 5000),
                    ('grpc.keepalive_permit_without_calls', True),
                    ('grpc.http2.max_pings_without_data', 0),
                    ('grpc.http2.min_time_between_pings_ms', 10000),
                    ('grpc.http2.min_ping_interval_without_data_ms', 300000),
                    ('grpc.max_receive_message_length', 4 * 1024 * 1024),  # 4MB
                    ('grpc.max_send_message_length', 4 * 1024 * 1024)  # 4MB
                ]
                
                print(f"Vision Pro 연결 시도 중... (IP: {self.ip}:12345)")
                
                # 연결 타임아웃 설정
                channel_options = options + [
                    ('grpc.initial_reconnect_backoff_ms', 1000),
                    ('grpc.max_reconnect_backoff_ms', 10000),
                    ('grpc.enable_retries', 1),
                    ('grpc.max_receive_message_length', 4 * 1024 * 1024),
                    ('grpc.max_send_message_length', 4 * 1024 * 1024)
                ]
                
                with grpc.insecure_channel(f"{self.ip}:12345", options=channel_options) as channel:
                    # 채널 상태 확인
                    try:
                        grpc.channel_ready_future(channel).result(timeout=10)
                        print("gRPC 채널 연결 확인됨")
                    except grpc.RpcError as e:
                        print(f"채널 연결 실패: {e}")
                        raise e
                    
                    stub = handtracking_pb2_grpc.HandTrackingServiceStub(channel)
                    responses = stub.StreamHandUpdates(request)
                    
                    print("gRPC 스트림 시작됨")
                    consecutive_failures = 0  # 성공하면 연속 실패 카운트 리셋
                    
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
                        
            except grpc.RpcError as e:
                consecutive_failures += 1
                print(f"gRPC 연결 오류 (연속 실패 {consecutive_failures}회): {e}")
                
                # 연결 상태를 None으로 설정하여 재연결 필요함을 알림
                self.latest = None
                
                # 지수 백오프 적용
                wait_time = min(2 ** min(consecutive_failures, 6), 60)  # 최대 60초
                print(f"{wait_time}초 후 재연결 시도...")
                time.sleep(wait_time)
                
            except Exception as e:
                consecutive_failures += 1
                print(f"예상치 못한 오류 (연속 실패 {consecutive_failures}회): {e}")
                self.latest = None
                time.sleep(5) 

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
    
    def restart_connection(self):
        """연결 재시작"""
        print("연결 재시작 중...")
        self.latest = None
        # 새로운 스트리밍 스레드 시작
        stream_thread = Thread(target=self.stream)
        stream_thread.daemon = True
        stream_thread.start()
        
        # 연결될 때까지 대기
        while self.latest is None:
            time.sleep(0.1)
        print("연결 재시작 완료!")
    
    def test_connection(self):
        """연결 테스트"""
        try:
            import socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            result = sock.connect_ex((self.ip, 12345))
            sock.close()
            return result == 0
        except Exception as e:
            print(f"연결 테스트 실패: {e}")
            return False
    

if __name__ == "__main__": 

    streamer = VisionProStreamer(ip = '10.29.230.57')
    while True: 

        latest = streamer.get_latest()
        # latest 변수 사용 (디버그용 출력 제거)