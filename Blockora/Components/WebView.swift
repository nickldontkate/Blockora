import SwiftUI
import WebKit

/// Thin WKWebView wrapper for in-app pages (§ marketing site link).
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) { webView.load(URLRequest(url: url)) }
}
