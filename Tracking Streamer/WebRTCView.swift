import SwiftUI
import WebKit

struct WebRTCView: UIViewRepresentable {
    let server: String // e.g., "<JETSON_IP>:8086"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        if let url = URL(string: "http://\(server)/") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}


