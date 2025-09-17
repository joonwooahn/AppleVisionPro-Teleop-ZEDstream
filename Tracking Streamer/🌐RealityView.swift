import SwiftUI
import RealityKit
import ARKit
import UIKit
import Foundation

struct 🌐RealityView: View {
    var model: 🥽AppModel
    @StateObject private var videoModel = VideoStreamModel()
    @State private var videoPlaneEntity: ModelEntity? = nil
    @State private var panelScale: Float = 1.0
    @State private var panelPosition: SIMD3<Float> = [0, 0, -1.0]

    var body: some View {
        RealityView { content, attachments in
            let resultLabelEntity = attachments.entity(for: Self.attachmentID)!
            resultLabelEntity.components.set(🧑HeadTrackingComponent())
            resultLabelEntity.name = 🧩Name.resultLabel

            // Create a video panel anchored to the user's head, 1.0 m in front
            let headAnchor = AnchorEntity(.head)
            let planeMesh = MeshResource.generatePlane(width: 1.20, height: 0.675)
            var material = UnlitMaterial()
            material.color = .init(tint: .black)
            let panel = ModelEntity(mesh: planeMesh, materials: [material])
            panel.position = panelPosition
            headAnchor.addChild(panel)
            content.add(headAnchor)
            self.videoPlaneEntity = panel
        } attachments: {
            Attachment(id: Self.attachmentID) {
            }
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    panelScale = max(0.2, min(4.0, Float(value.magnification)))
                    if let panel = self.videoPlaneEntity {
                        panel.scale = [panelScale, panelScale, panelScale]
                    }
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    // Convert point translation to small meter offsets
                    let dx = Float(value.translation.width) * 0.001
                    let dy = Float(value.translation.height) * 0.001
                    panelPosition.x = dx
                    panelPosition.y = -dy
                    if let panel = self.videoPlaneEntity {
                        panel.position = panelPosition
                    }
                }
        )
        .task { self.model.run() }
        .task { await self.model.processDeviceAnchorUpdates() }
        .task { self.model.startserver() }
        .task(priority: .low) { await self.model.processReconstructionUpdates() }
        .task {
            // Start MJPEG snapshot polling inside immersive space (only for mjpeg mode)
            let mode = UserDefaults.standard.string(forKey: "stream_mode") ?? "mjpeg"
            if mode == "mjpeg", let ip = UserDefaults.standard.string(forKey: "server_ip"), let url = URL(string: "http://\(ip):8080/snapshot.jpg") {
                videoModel.start(url: url, fps: 10)
            }
            for await img in videoModel.$image.values {
                guard let plane = self.videoPlaneEntity, let image = img, let cg = image.cgImage else { continue }
                if let tex = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) {
                    var mat = UnlitMaterial()
                    mat.color = .init(tint: .white, texture: .init(tex))
                    plane.model?.materials = [mat]
                }
            }
        }
        // WebRTC는 WKWebView로 처리하므로 immersive 패널에서는 MJPEG만 렌더링
    }
    static let attachmentID: String = "resultLabel"
}



