import SwiftUI
import WebKit

struct CardWebView: NSViewRepresentable {
    let html: String
    let css: String
    let baseURL: URL?

    func makeNSView(context _: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context _: Context) {
        let fullHTML = buildReviewerHTML(body: html, css: css)
        webView.loadHTMLString(fullHTML, baseURL: baseURL)
    }
}

private func buildReviewerHTML(body: String, css: String) -> String {
    """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
    \(css)
    </style>
    </head>
    <body>
    <div id="qa">\(body)</div>
    </body>
    </html>
    """
}
