import RealityKit
import ARKit
import SwiftUI

// 1. 시선 추적을 받을 엔티티에 부착할 컴포넌트
struct 👁️GazeTrackingComponent: Component, Codable {
    // 이 컴포넌트는 표시(marker) 역할만 합니다.
    init() {}
}

// 2. 시선 추적 로직을 처리하는 시스템
struct 👁️GazeTrackingSystem: System {
    // 👁️GazeTrackingComponent를 가진 엔티티를 찾기 위한 쿼리
    private static let query = EntityQuery(where: .has(👁️GazeTrackingComponent.self))
    
    // ARKit 세션과 데이터 제공자는 HeadTrackingSystem과 동일하게 사용합니다.
    private let session = ARKitSession()
    private let provider = WorldTrackingProvider()
    
    init(scene: RealityKit.Scene) {
        self.setUpSession()
    }
    
    private func setUpSession() {
        Task {
            do {
                try await self.session.run([self.provider])
            } catch {
                // 실제 앱에서는 에러 처리를 해주어야 합니다.
                fatalError("ARKit Session을 시작하는데 실패했습니다: \(error)")
            }
        }
    }
    
    // 매 프레임마다 호출되는 업데이트 함수
    func update(context: SceneUpdateContext) {
        // 👁️GazeTrackingComponent가 부착된 엔티티들을 가져옵니다.
        let entities = context.scene.performQuery(Self.query).map { $0 }
        
        // 엔티티가 없으면 아무 작업도 하지 않습니다.
        guard !entities.isEmpty,
              let deviceAnchor = self.provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }
        
        // 1. 시선(Gaze) 데이터 가져오기
        // deviceAnchor에서 시선의 원점(origin)과 방향(direction)을 얻습니다.
        let gazeOrigin = deviceAnchor.originFromAnchorTransform.columns.3.xyz
        
        // 더 간단한 접근: 패널 중심을 향한 방향 계산
        let panelCenter = SIMD3<Float>(0, -0.1, -0.83)
        let gazeDirection = normalize(panelCenter - gazeOrigin)
        
        // 디버그: 시선 정보 출력
        print("[Gaze] Origin: \(gazeOrigin), Direction: \(gazeDirection)")

        // 2. 레이캐스팅(Ray Casting) 수행
        // 시선 방향으로 광선을 쏘아, 가상 공간의 객체와 처음 충돌하는 지점을 찾습니다.
        let rayEnd = gazeOrigin + gazeDirection * 10.0  // 10미터 거리까지 레이캐스팅
        
        // 여러 레이캐스팅 방법 시도
        var hitResult: CollisionCastHit? = nil
        
        // 1. 기본 레이캐스팅 시도
        if let result = context.scene.raycast(
            from: gazeOrigin, 
            to: rayEnd, 
            query: .nearest, 
            mask: .all, 
            relativeTo: nil
        ).first {
            hitResult = result
        }
        
        // 2. 더 긴 거리로 레이캐스팅 시도
        if hitResult == nil {
            let longRayEnd = gazeOrigin + gazeDirection * 50.0  // 50미터까지
            if let result = context.scene.raycast(
                from: gazeOrigin, 
                to: longRayEnd, 
                query: .nearest, 
                mask: .all, 
                relativeTo: nil
            ).first {
                hitResult = result
            }
        }
        
        // 3. 결과 처리
        if let result = hitResult {
            // 디버그: 레이캐스팅 결과 출력
            print("[Gaze] Raycast hit at: \(result.position)")
            
            // 엔티티 위치 업데이트 (충돌 지점의 위치 사용)
            for entity in entities {
                entity.position = result.position
            }
        } else {
            print("[Gaze] No raycast hit - trying manual calculation")
            
            // 레이캐스팅이 실패하면 수동으로 ZED 패널과의 교점 계산
            let panelZ: Float = -0.83
            let panelCenterY: Float = -0.1  // 패널 중심 Y 위치
            print("[Gaze] Manual calc - gazeOrigin: \(gazeOrigin), gazeDirection: \(gazeDirection)")
            print("[Gaze] Manual calc - panelZ: \(panelZ), panelCenterY: \(panelCenterY), gazeOrigin.z: \(gazeOrigin.z)")
            
            if gazeDirection.z != 0 {
                let t = (panelZ - gazeOrigin.z) / gazeDirection.z
                print("[Gaze] Manual calc - t: \(t)")
                
                if t > 0 {
                    let intersectionX = gazeOrigin.x + t * gazeDirection.x
                    let intersectionY = gazeOrigin.y + t * gazeDirection.y
                    
                    print("[Gaze] Manual calc - intersection: (\(intersectionX), \(intersectionY), \(panelZ))")
                    
                    // 패널 크기 내에 있는지 확인 (원래 크기에 맞춰 조정)
                    let panelWidth: Float = 0.6  // 패널 너비의 절반 (1.20/2)
                    let panelHeight: Float = 0.3375  // 패널 높이의 절반 (0.675/2)
                    
                    print("[Gaze] Manual calc - checking bounds: |\(intersectionX)| <= \(panelWidth), |\(intersectionY - panelCenterY)| <= \(panelHeight)")
                    
                    if abs(intersectionX) <= panelWidth && abs(intersectionY - panelCenterY) <= panelHeight {
                        print("[Gaze] Manual calculation hit at: (\(intersectionX), \(intersectionY), \(panelZ))")
                        for entity in entities {
                            entity.position = [intersectionX, intersectionY, panelZ + 0.01]
                        }
                    } else {
                        print("[Gaze] Manual calc - outside panel bounds")
                    }
                } else {
                    print("[Gaze] Manual calc - t <= 0, no intersection")
                }
            } else {
                print("[Gaze] Manual calc - gazeDirection.z is 0")
            }
        }
    }
}

// SIMD3<Float>의 xyz 속성을 사용하기 위한 작은 확장
extension simd_float4 {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}
