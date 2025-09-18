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
    @State private var gazeIndicator: ModelEntity? = nil

    var body: some View {
        RealityView { content in
            // Create a video panel anchored to the user's head, 1.0 m in front
            let headAnchor = AnchorEntity(.head)
            let planeMesh = MeshResource.generatePlane(width: 1.20, height: 0.675)
            var material = UnlitMaterial()
            material.color = .init(tint: .black)
            let panel = ModelEntity(mesh: planeMesh, materials: [material])
            panel.position = [0, -0.1, -0.83]  // 아래로 이동 (Y축 -0.1)
            headAnchor.addChild(panel)
            content.add(headAnchor)
            self.videoPlaneEntity = panel
            
            // Create gaze indicator (small red dot)
            let gazeSphere = MeshResource.generateSphere(radius: 0.005)
            var gazeMaterial = UnlitMaterial()
            gazeMaterial.color = .init(tint: .red)
            let gazeIndicator = ModelEntity(mesh: gazeSphere, materials: [gazeMaterial])
            gazeIndicator.position = [0, 0, -0.83]  // 패널 앞쪽에 위치
            headAnchor.addChild(gazeIndicator)
            self.gazeIndicator = gazeIndicator
            
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
            // Update gaze indicator position
            while true {
                await updateGazeIndicator()
                try? await Task.sleep(nanoseconds: 16_666_667) // ~60fps
            }
        }
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
    
    private func updateGazeIndicator() async {
        guard let gazeIndicator = self.gazeIndicator,
              let panel = self.videoPlaneEntity else { return }
        
        let eyeData = DataManager.shared.latestEyeTrackingData
        
        // 시선과 패널의 교점 계산
        let gazeOrigin = eyeData.gazeOrigin
        let gazeDirection = eyeData.gazeDirection
        
        // 패널은 Z = -0.83 평면에 위치
        let panelZ: Float = -0.83
        
        // 시선이 패널과 교차하는지 확인
        if gazeDirection.z != 0 {
            let t = (panelZ - gazeOrigin.z) / gazeDirection.z
            
            if t > 0 { // 시선이 앞쪽을 향함
                let intersectionX = gazeOrigin.x + t * gazeDirection.x
                let intersectionY = gazeOrigin.y + t * gazeDirection.y
                
                // 패널 크기 내에 있는지 확인 (width: 1.20, height: 0.675)
                let panelWidth: Float = 0.6  // 패널 너비의 절반
                let panelHeight: Float = 0.3375  // 패널 높이의 절반
                
                if abs(intersectionX) <= panelWidth && abs(intersectionY - (-0.1)) <= panelHeight {
                    // 패널 내부에 있으면 빨간 점 표시
                    gazeIndicator.position = [intersectionX, intersectionY, panelZ + 0.01]
                    gazeIndicator.isEnabled = true
                } else {
                    // 패널 외부에 있으면 숨김
                    gazeIndicator.isEnabled = false
                }
            } else {
                gazeIndicator.isEnabled = false
            }
        } else {
            gazeIndicator.isEnabled = false
        }
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



