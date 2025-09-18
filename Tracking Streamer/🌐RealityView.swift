import SwiftUI
import RealityKit
import ARKit
import UIKit
import Foundation

struct 🌐RealityView: View {
    var model: 🥽AppModel
    @StateObject private var videoModel = VideoStreamModel()
    @State private var videoPlaneEntity: ModelEntity? = nil
    @State private var isLoading: Bool = true

    var body: some View {
        RealityView { content in
            // Create a video panel anchored to the user's head, 1.0 m in front
            let headAnchor = AnchorEntity(.head)
            let planeMesh = MeshResource.generatePlane(width: 1.20, height: 0.675)
            var material = UnlitMaterial()
            material.color = .init(tint: .black)
            let panel = ModelEntity(mesh: planeMesh, materials: [material])
            panel.position = [0, -0.1, -0.83]  // 아래로 이동 (Y축 -0.1)
            
            // 레이캐스팅을 위해 충돌 컴포넌트 추가
            let collisionShape = ShapeResource.generateBox(width: 1.20, height: 0.675, depth: 0.01)
            panel.components.set(CollisionComponent(shapes: [collisionShape]))
            panel.components.set(InputTargetComponent())
            
            headAnchor.addChild(panel)
            content.add(headAnchor)
            self.videoPlaneEntity = panel
            
            // Create loading text texture
            if isLoading {
                let loadingText = "Loading..."
                let textImage = createTextImage(text: loadingText, size: CGSize(width: 400, height: 100))
                if let cgImage = textImage.cgImage,
                   let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color)) {
                    var loadingMaterial = UnlitMaterial()
                    loadingMaterial.color = .init(tint: .white, texture: .init(texture))
                    panel.model?.materials = [loadingMaterial]
                }
            }
        }
        .task { self.model.run() }
        .task { await self.model.processDeviceAnchorUpdates() }
        .task { self.model.startserver() }
        .task(priority: .low) { await self.model.processReconstructionUpdates() }
        .task {
            // Start snapshot polling inside immersive space for mjpeg or webrtc modes
            let mode = UserDefaults.standard.string(forKey: "stream_mode") ?? "mjpeg"
            if let ip = UserDefaults.standard.string(forKey: "server_ip") {
                if mode == "mjpeg", let url = URL(string: "http://\(ip):8080/snapshot.jpg") {
                    videoModel.start(url: url, fps: 15)
                } else if mode == "webrtc", let url = URL(string: "http://\(ip):8086/snapshot.jpg") {
                    videoModel.start(url: url, fps: 15)
                }
            }
            for await img in videoModel.$image.values {
                guard let plane = self.videoPlaneEntity, let image = img, let cg = image.cgImage else { continue }
                if let tex = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) {
                    var mat = UnlitMaterial()
                    mat.color = .init(tint: .white, texture: .init(tex))
                    plane.model?.materials = [mat]
                    // 첫 번째 이미지가 로드되면 로딩 상태 해제
                    if isLoading {
                        isLoading = false
                    }
                }
            }
        }
        // Removed WebRTC WKWebView overlay to avoid black covering in immersive
        // WebRTC는 WKWebView로 처리하므로 immersive 패널에서는 MJPEG만 렌더링
    }
    
    private func createTextImage(text: String, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Black background
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // White text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
}



