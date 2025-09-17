#!/usr/bin/env python3
"""
Simple H.264 TCP client to test the stream
"""
import socket
import sys

def test_h264_stream(host, port):
    try:
        # Connect to the H.264 TCP server
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect((host, port))
        print(f"Connected to {host}:{port}")
        
        # Read some data
        data = sock.recv(1024)
        print(f"Received {len(data)} bytes")
        
        # Look for H.264 start codes
        start_codes = []
        for i in range(len(data) - 3):
            if data[i:i+3] == b'\x00\x00\x01':
                start_codes.append(i)
            elif i < len(data) - 4 and data[i:i+4] == b'\x00\x00\x00\x01':
                start_codes.append(i)
        
        print(f"Found {len(start_codes)} start codes")
        
        # Check for SPS/PPS
        if len(data) > 4:
            nal_type = data[4] & 0x1F
            print(f"First NAL type: {nal_type} ({'SPS' if nal_type == 7 else 'PPS' if nal_type == 8 else 'Other'})")
        
        sock.close()
        return True
        
    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    host = sys.argv[1] if len(sys.argv) > 1 else "172.30.1.60"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
    
    print(f"Testing H.264 stream from {host}:{port}")
    success = test_h264_stream(host, port)
    sys.exit(0 if success else 1)
