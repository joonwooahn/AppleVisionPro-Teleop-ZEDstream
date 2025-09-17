import Foundation
import SwiftUI
import UIKit

final class VideoStreamModel: ObservableObject {
    @Published var image: UIImage? = nil
    @Published var isRunning: Bool = false

    private var timer: Timer?
    private var currentURL: URL? = nil

    func start(url: URL, fps: Int = 10) {
        guard !isRunning else { return }
        isRunning = true
        currentURL = url
        let interval = 1.0 / Double(max(1, fps))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self, let current = self.currentURL else { return }
            self.fetchSnapshot(url: current)
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        currentURL = nil
    }

    private func fetchSnapshot(url: URL) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 1.0
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard error == nil, let data = data, let uiImage = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.image = uiImage
            }
        }
        task.resume()
    }
}


