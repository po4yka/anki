import AVFoundation
import SwiftUI
import WebKit

#if os(macOS)
    public struct CardWebView: NSViewRepresentable {
        public let html: String
        public let css: String
        public let baseURL: URL?
        public var onPlayAudio: ((String) -> Void)?

        public init(html: String, css: String, baseURL: URL?, onPlayAudio: ((String) -> Void)? = nil) {
            self.html = html
            self.css = css
            self.baseURL = baseURL
            self.onPlayAudio = onPlayAudio
        }

        public func makeCoordinator() -> Coordinator {
            Coordinator(onPlayAudio: onPlayAudio)
        }

        public func makeNSView(context: Context) -> WKWebView {
            makeWebView(context: context)
        }

        public func updateNSView(_ webView: WKWebView, context: Context) {
            updateWebView(webView, context: context)
        }
    }
#else
    public struct CardWebView: UIViewRepresentable {
        public let html: String
        public let css: String
        public let baseURL: URL?
        public var onPlayAudio: ((String) -> Void)?

        public init(html: String, css: String, baseURL: URL?, onPlayAudio: ((String) -> Void)? = nil) {
            self.html = html
            self.css = css
            self.baseURL = baseURL
            self.onPlayAudio = onPlayAudio
        }

        public func makeCoordinator() -> Coordinator {
            Coordinator(onPlayAudio: onPlayAudio)
        }

        public func makeUIView(context: Context) -> WKWebView {
            makeWebView(context: context)
        }

        public func updateUIView(_ webView: WKWebView, context: Context) {
            updateWebView(webView, context: context)
        }
    }
#endif

private extension CardWebView {
    func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "ankiPlay")
        let webView = WKWebView(frame: .zero, configuration: config)
        #if os(macOS)
            webView.setValue(false, forKey: "drawsBackground")
        #else
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
        #endif
        return webView
    }

    func updateWebView(_ webView: WKWebView, context: Context) {
        context.coordinator.onPlayAudio = onPlayAudio
        if context.coordinator.isLoaded, context.coordinator.lastCSS == css {
            let escaped = escapeForJS(html)
            webView.evaluateJavaScript("updateContent('\(escaped)')")
        } else {
            let fullHTML = buildReviewerHTML(body: html, css: css)
            webView.loadHTMLString(fullHTML, baseURL: baseURL)
            context.coordinator.lastCSS = css
            context.coordinator.isLoaded = true
        }
    }
}

public extension CardWebView {
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onPlayAudio: ((String) -> Void)?
        var isLoaded = false
        var lastCSS = ""

        public init(onPlayAudio: ((String) -> Void)?) {
            self.onPlayAudio = onPlayAudio
        }

        public func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "ankiPlay", let filename = message.body as? String {
                onPlayAudio?(filename)
            }
        }
    }
}

private func escapeForJS(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "'", with: "\\'")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "")
}

private func mathjaxHeadHTML() -> String {
    """
    <script>
    MathJax = {
        tex: { inlineMath: [['\\\\(', '\\\\)']], displayMath: [['\\\\[', '\\\\]']] },
        svg: { fontCache: 'local' },
        options: { skipHtmlTags: ['script', 'noscript', 'style', 'textarea', 'code'] },
        startup: { typeset: true }
    };
    </script>
    <script src="mathjax/tex-svg.js" id="MathJax-script" async></script>
    """
}

private func reviewerScript() -> String {
    """
    <script>
    function bindAudioButtons() {
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
    }
    function updateContent(html) {
        var qa = document.getElementById('qa');
        qa.innerHTML = html;
        if (window.MathJax && MathJax.typesetPromise) {
            MathJax.typesetClear([qa]);
            MathJax.typesetPromise([qa]);
        }
        bindAudioButtons();
        qa.querySelectorAll('script').forEach(function(old) {
            var s = document.createElement('script');
            s.textContent = old.textContent;
            old.parentNode.replaceChild(s, old);
        });
    }
    bindAudioButtons();
    </script>
    """
}

private func buildReviewerHTML(body: String, css: String) -> String {
    """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    \(mathjaxHeadHTML())
    <script src="image-occlusion.js"></script>
    <style>
    \(css)
    .replay-button { cursor: pointer; }
    .replay-button svg:not(.MathJax) { width: 32px; height: 32px; fill: currentColor; }
    mjx-container { overflow-x: auto; overflow-y: hidden; max-width: 100%; }
    mjx-container[display="true"] { display: block; text-align: center; margin: 12px 0; }
    #image-occlusion-container { position: relative; display: inline-block; }
    #image-occlusion-canvas { position: absolute; top: 0; left: 0; pointer-events: none; }
    </style>
    </head>
    <body>
    <div id="qa">\(body)</div>
    \(reviewerScript())
    </body>
    </html>
    """
}
