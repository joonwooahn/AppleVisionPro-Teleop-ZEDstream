import SwiftUI

@main
struct VisionProTeleopApp: App {
    @StateObject private var appModel = 🥽AppModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    // 앱이 백그라운드로 갈 때
                    print("앱이 백그라운드로 이동 중...")
                    appModel.pauseTracking()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // 앱이 포그라운드로 올 때
                    print("앱이 포그라운드로 복귀 중...")
                    appModel.resumeTracking()
                    // 포그라운드 복귀 시 서버 재시작
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        appModel.startserver()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    // 앱이 완전히 종료될 때
                    print("앱 종료 중...")
                    appModel.stopTracking()
                }
        }
        .windowResizability(.contentSize)
        ImmersiveSpace(id: "immersiveSpace") {
            🌐RealityView(model: appModel)
        }
    }
    
    init() {
        🧑HeadTrackingComponent.registerComponent()
        🧑HeadTrackingSystem.registerSystem()
    }
}

