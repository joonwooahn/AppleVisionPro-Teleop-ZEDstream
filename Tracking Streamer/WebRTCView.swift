import SwiftUI
import WebKit

struct WebRTCView: UIViewRepresentable {
    let server: String // e.g., "<JETSON_IP>:8086"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        
        // Load the WebRTC page with autostart
        if let url = URL(string: "http://\(server)/?server=\(server)&autostart=1") {
            let request = URLRequest(url: url)
            webView.load(request)
        }
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}


