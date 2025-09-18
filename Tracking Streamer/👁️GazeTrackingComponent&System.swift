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
        let gazeDirection = deviceAnchor.originFromAnchorTransform.columns.2.xyz * -1 // Z축의 반대 방향이 정면입니다.

        // 2. 레이캐스팅(Ray Casting) 수행
        // 시선 방향으로 광선을 쏘아, 가상 공간의 객체와 처음 충돌하는 지점을 찾습니다.
        let rayEnd = gazeOrigin + gazeDirection * 10.0  // 10미터 거리까지 레이캐스팅
        
        if let result = context.scene.raycast(
            from: gazeOrigin, 
            to: rayEnd, 
            query: .nearest, 
            mask: .all, 
            relativeTo: nil
        ).first {
            
            // 3. 엔티티 위치 업데이트
            // 찾은 충돌 지점의 위치로 모든 엔티티를 이동시킵니다.
            for entity in entities {
                entity.position = result.position
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
