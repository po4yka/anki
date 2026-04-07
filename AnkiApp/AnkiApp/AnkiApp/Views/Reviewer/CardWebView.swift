import AVFoundation
import SwiftUI
import WebKit

struct CardWebView: NSViewRepresentable {
    let html: String
    let css: String
    let baseURL: URL?
    var onPlayAudio: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onPlayAudio: onPlayAudio)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "ankiPlay")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onPlayAudio = onPlayAudio
        let fullHTML = buildReviewerHTML(body: html, css: css)
        webView.loadHTMLString(fullHTML, baseURL: baseURL)
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var onPlayAudio: ((String) -> Void)?

        init(onPlayAudio: ((String) -> Void)?) {
            self.onPlayAudio = onPlayAudio
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "ankiPlay", let filename = message.body as? String {
                onPlayAudio?(filename)
            }
        }
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
    .replay-button { cursor: pointer; }
    .replay-button svg { width: 32px; height: 32px; fill: currentColor; }
    </style>
    </head>
    <body>
    <div id="qa">\(body)</div>
    <script>
    document.querySelectorAll('.replay-button').forEach(function(btn) {
        btn.addEventListener('click', function() {
            var file = this.getAttribute('data-file');
            if (file) { window.webkit.messageHandlers.ankiPlay.postMessage(file); }
        });
    });
    document.querySelectorAll('a[href^="playsound:"]').forEach(function(a) {
        a.addEventListener('click', function(e) {
            e.preventDefault();
            var file = this.getAttribute('href').replace('playsound:', '');
            if (file) { window.webkit.messageHandlers.ankiPlay.postMessage(file); }
        });
    });
    </script>
    </body>
    </html>
    """
}
