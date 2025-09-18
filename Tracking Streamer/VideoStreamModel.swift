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
                return
            }
            
            guard let data = data else {
                return
            }
            
            guard let image = UIImage(data: data) else {
                return
            }
            
            DispatchQueue.main.async {
                self.image = image
            }
        }.resume()
    }
    
    deinit {
        stop()
    }
}
