#!/usr/bin/env python3
"""
Vision Pro 연결 상태 모니터링 유틸리티
Apple Vision Pro와의 gRPC 연결 상태를 실시간으로 모니터링합니다.
"""

import time
import socket
import subprocess
import sys
from threading import Thread
import argparse

class ConnectionMonitor:
    def __init__(self, vision_pro_ip="10.29.230.57", port=12345, check_interval=2):
        self.vision_pro_ip = vision_pro_ip
        self.port = port
        self.check_interval = check_interval
        self.is_monitoring = False
        
    def check_port_connectivity(self):
        """포트 연결 상태 확인"""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(3)
            result = sock.connect_ex((self.vision_pro_ip, self.port))
            sock.close()
            return result == 0
        except Exception as e:
            print(f"포트 연결 확인 중 오류: {e}")
            return False
    
    def ping_vision_pro(self):
        """Vision Pro 장치 ping 테스트"""
        try:
            # ping 명령어 실행 (Linux/macOS)
            result = subprocess.run(
                ['ping', '-c', '1', '-W', '3', self.vision_pro_ip], 
                capture_output=True, 
                text=True, 
                timeout=5
            )
            return result.returncode == 0
        except Exception as e:
            print(f"Ping 테스트 중 오류: {e}")
            return False
    
    def monitor_connection(self):
        """연결 상태 모니터링"""
        print(f"Vision Pro 연결 상태 모니터링 시작...")
        print(f"대상 IP: {self.vision_pro_ip}:{self.port}")
        print(f"체크 간격: {self.check_interval}초")
        print("-" * 50)
        
        self.is_monitoring = True
        consecutive_failures = 0
        
        while self.is_monitoring:
            timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
            
            # 네트워크 연결 확인
            ping_ok = self.ping_vision_pro()
            port_ok = self.check_port_connectivity()
            
            if ping_ok and port_ok:
                print(f"[{timestamp}] ✅ 연결 정상 - 네트워크: OK, 포트: OK")
                consecutive_failures = 0
            elif ping_ok and not port_ok:
                print(f"[{timestamp}] ⚠️  부분 연결 - 네트워크: OK, 포트: FAIL (gRPC 서버 미실행?)")
                consecutive_failures += 1
            else:
                print(f"[{timestamp}] ❌ 연결 실패 - 네트워크: FAIL, 포트: FAIL")
                consecutive_failures += 1
            
            # 연속 실패 시 경고
            if consecutive_failures >= 3:
                print(f"[{timestamp}] 🚨 경고: {consecutive_failures}회 연속 연결 실패!")
                print("   → Vision Pro 앱이 실행 중인지 확인하세요")
                print("   → 네트워크 연결을 확인하세요")
            
            time.sleep(self.check_interval)
    
    def stop_monitoring(self):
        """모니터링 중지"""
        self.is_monitoring = False
        print("\n모니터링을 중지합니다.")

def main():
    parser = argparse.ArgumentParser(description="Vision Pro 연결 상태 모니터링")
    parser.add_argument("--ip", default="10.29.230.57", help="Vision Pro IP 주소")
    parser.add_argument("--port", type=int, default=12345, help="gRPC 포트 번호")
    parser.add_argument("--interval", type=int, default=2, help="체크 간격 (초)")
    
    args = parser.parse_args()
    
    monitor = ConnectionMonitor(args.ip, args.port, args.interval)
    
    try:
        monitor.monitor_connection()
    except KeyboardInterrupt:
        print("\n사용자에 의해 중단됨")
        monitor.stop_monitoring()
    except Exception as e:
        print(f"모니터링 중 오류 발생: {e}")
        monitor.stop_monitoring()

if __name__ == "__main__":
    main()
