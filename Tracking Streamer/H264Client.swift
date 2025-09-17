import Foundation
import Network
import UIKit

// Simple TCP client that reads Annex B H.264 bytestream and feeds VideoDecoder
final class H264TCPClient: ObservableObject {
    @Published var image: UIImage? = nil

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "h264.tcp.client")
    private let decoder = H264AnnexBDecoder()

    private var buffer = Data()

    func start(host: String, port: UInt16) {
        print("[H264Client] Starting connection to \(host):\(port)")
        decoder.onFrame = { [weak self] cg in
            print("[H264Client] Received frame")
            self?.image = UIImage(cgImage: cg)
        }
        let params = NWParameters.tcp
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        self.connection = conn
        conn.stateUpdateHandler = { state in
            print("[H264Client] Connection state: \(state)")
            switch state {
            case .ready: 
                print("[H264Client] Connected, starting receive loop")
                self.receiveLoop()
            case .failed(let error):
                print("[H264Client] Connection failed: \(error)")
            default: break
            }
        }
        conn.start(queue: queue)
    }

    func stop() {
        connection?.cancel()
        connection = nil
        buffer.removeAll(keepingCapacity: false)
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, let chunk = data, !chunk.isEmpty else { 
                if let error = error {
                    print("[H264Client] Receive error: \(error)")
                }
                return 
            }
            print("[H264Client] Received \(chunk.count) bytes")
            self.buffer.append(chunk)
            self.consumeNALs()
            if isComplete == false && error == nil {
                self.receiveLoop()
            }
        }
    }

    private func consumeNALs() {
        // Annex B: 0x000001 or 0x00000001 start codes
        func findStart(_ data: Data, from: Int) -> Int? {
            var i = from
            let n = data.count
            while i + 3 < n {
                if data[i] == 0 && data[i+1] == 0 && data[i+2] == 1 { return i }
                if i + 4 < n && data[i] == 0 && data[i+1] == 0 && data[i+2] == 0 && data[i+3] == 1 { return i }
                i += 1
            }
            return nil
        }

        var idx = findStart(buffer, from: 0)
        while let start = idx {
            let nextSearchStart = start + 3
            let next = findStart(buffer, from: nextSearchStart)
            if let end = next {
                let nal = buffer[start..<end]
                feed(nal: stripStartCode(nal))
                buffer.removeSubrange(0..<end)
                idx = findStart(buffer, from: 0)
            } else {
                // wait for more data
                break
            }
        }
    }

    private func stripStartCode(_ data: Data) -> Data {
        var d = data
        if d.prefix(4) == Data([0,0,0,1]) { return d.advanced(by: 4) }
        if d.prefix(3) == Data([0,0,1]) { return d.advanced(by: 3) }
        return d
    }

    private var sps: Data? = nil
    private var pps: Data? = nil
    private var configured = false

    private func feed(nal: Data) {
        guard nal.count > 0 else { return }
        let naluType = nal[0] & 0x1F
        switch naluType {
        case 7: // SPS
            sps = nal
        case 8: // PPS
            pps = nal
        default:
            break
        }

        if !configured, let sps, let pps {
            decoder.configure(withSPS: sps, pps: pps)
            configured = true
        }

        if configured {
            decoder.decode(nal: nal)
        }
    }
}


