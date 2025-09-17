import SwiftUI

struct VideoStreamView: View {
    @StateObject private var model = VideoStreamModel()
    let snapshotURL: URL
    let fps: Int

    init(host: String, port: Int = 8080, fps: Int = 10) {
        self.snapshotURL = URL(string: "http://\(host):\(port)/snapshot.jpg")!
        self.fps = fps
    }

    var body: some View {
        Group {
            if let img = model.image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 16))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.2))
                    ProgressView().tint(.white)
                }
            }
        }
        .task {
            model.start(url: snapshotURL, fps: fps)
        }
        .onDisappear { model.stop() }
    }
}

struct H264Preview: View {
    @StateObject private var client = H264TCPClient()
    let host: String
    let port: UInt16

    var body: some View {
        Group {
            if let img = client.image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 16))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.2))
                    ProgressView().tint(.white)
                }
            }
        }
        .task { client.start(host: host, port: port) }
        .onDisappear { client.stop() }
    }
}

struct WebRTCPreview: View {
    let server: String
    var body: some View {
        WebRTCView(server: server)
            .clipShape(.rect(cornerRadius: 16))
    }
}

// Helper: ask the user to input IP or auto-use the iPhone WiFi subnet logic later.
// Placeholder removed; ContentView writes 'server_ip' into UserDefaults and RealityView reads it.

import RealityKit

enum 🧩Model {
    static func fingerTip(_ selected: Bool = false) -> ModelComponent {
        .init(mesh: .generateSphere(radius: 0.005),
              materials: [SimpleMaterial(color: selected ? .red : .blue,
                                         isMetallic: true)])
    }
    static func line(_ length: Float) -> ModelComponent {
        ModelComponent(mesh: .generateBox(width: 0.01,
                                          height: 0.01,
                                          depth: length,
                                          cornerRadius: 0.005),
                       materials: [SimpleMaterial(color: .white, isMetallic: true)])
    }
}
