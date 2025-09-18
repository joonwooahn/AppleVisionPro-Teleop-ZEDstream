import SwiftUI
import UIKit
import Combine

class VideoStreamModel: ObservableObject {
    @Published var image: UIImage? = nil
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    
    func start(url: URL, fps: Int) {
        stop()
        
        let interval = 1.0 / Double(fps)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            self.fetchImage(from: url)
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func fetchImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("[VideoStreamModel] Error: \(error)")
                return
            }
            
            guard let data = data else {
                print("[VideoStreamModel] No data")
                return
            }
            
            guard let image = UIImage(data: data) else {
                print("[VideoStreamModel] Failed to create image from \(data.count) bytes")
                return
            }
            
            print("[VideoStreamModel] Success: \(image.size)")
            DispatchQueue.main.async {
                self.image = image
            }
        }.resume()
    }
    
    deinit {
        stop()
    }
}
