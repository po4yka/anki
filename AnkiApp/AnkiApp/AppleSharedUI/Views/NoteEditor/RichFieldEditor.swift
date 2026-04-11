import SwiftUI
import WebKit

#if os(macOS)
    public struct RichFieldEditor: NSViewRepresentable {
        @Binding public var html: String
        public var onContentChange: ((String) -> Void)?
        public var onCoordinatorReady: ((Coordinator) -> Void)?

        public init(
            html: Binding<String>,
            onContentChange: ((String) -> Void)? = nil,
            onCoordinatorReady: ((Coordinator) -> Void)? = nil
        ) {
            _html = html
            self.onContentChange = onContentChange
            self.onCoordinatorReady = onCoordinatorReady
        }

        public func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        public func makeNSView(context: Context) -> WKWebView {
            makeWebView(context: context)
        }

        public func updateNSView(_ webView: WKWebView, context: Context) {
            updateWebView(webView, context: context)
        }
    }
#else
    public struct RichFieldEditor: UIViewRepresentable {
        @Binding public var html: String
        public var onContentChange: ((String) -> Void)?
        public var onCoordinatorReady: ((Coordinator) -> Void)?

        public init(
            html: Binding<String>,
            onContentChange: ((String) -> Void)? = nil,
            onCoordinatorReady: ((Coordinator) -> Void)? = nil
        ) {
            _html = html
            self.onContentChange = onContentChange
            self.onCoordinatorReady = onCoordinatorReady
        }

        public func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        public func makeUIView(context: Context) -> WKWebView {
            makeWebView(context: context)
        }

        public func updateUIView(_ webView: WKWebView, context: Context) {
            updateWebView(webView, context: context)
        }
    }
#endif

private extension RichFieldEditor {
    func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "contentChanged")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        let htmlPage = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 14px;
                margin: 0;
                padding: 8px;
                min-height: 100%;
            }
            #editor {
                outline: none;
                min-height: 50px;
                word-wrap: break-word;
            }
        </style>
        <script>
            window.MathJax = {
                tex: { inlineMath: [['\\\\(','\\\\)']], displayMath: [['\\\\[','\\\\]']] },
                startup: { typeset: true }
            };
        </script>
        <script id="MathJax-script" async
            src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js">
        </script>
        </head>
        <body>
        <div id="editor" contenteditable="true">\(html)</div>
        <script>
            const editor = document.getElementById('editor');
            editor.addEventListener('input', function() {
                window.webkit.messageHandlers.contentChanged.postMessage(editor.innerHTML);
                typesetMath();
            });
            function setContent(html) {
                editor.innerHTML = html;
                typesetMath();
            }
            function getContent() {
                return editor.innerHTML;
            }
            function execCommand(cmd, value) {
                document.execCommand(cmd, false, value || null);
                window.webkit.messageHandlers.contentChanged.postMessage(editor.innerHTML);
            }
            function getSelectedText() {
                return window.getSelection().toString();
            }
            function insertHTML(html) {
                document.execCommand('insertHTML', false, html);
                window.webkit.messageHandlers.contentChanged.postMessage(editor.innerHTML);
                typesetMath();
            }
            function typesetMath() {
                if (typeof MathJax !== 'undefined' && MathJax.typesetPromise) {
                    MathJax.typesetPromise([editor]).catch(function() {});
                }
            }
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(htmlPage, baseURL: nil)
        onCoordinatorReady?(context.coordinator)
        return webView
    }

    func updateWebView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastSetHTML != html {
            context.coordinator.lastSetHTML = html
            let escaped = html
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            webView.evaluateJavaScript("setContent('\(escaped)')")
        }
    }
}

public extension RichFieldEditor {
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        public let parent: RichFieldEditor
        public weak var webView: WKWebView?
        public var lastSetHTML: String = ""

        public init(_ parent: RichFieldEditor) {
            self.parent = parent
        }

        public func userContentController(
            _: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let content = message.body as? String else { return }
            lastSetHTML = content
            DispatchQueue.main.async {
                self.parent.html = content
                self.parent.onContentChange?(content)
            }
        }

        public func executeCommand(_ command: String, value: String? = nil) {
            let valueArg = value.map { "'\($0)'" } ?? "null"
            webView?.evaluateJavaScript("execCommand('\(command)', \(valueArg))")
        }

        public func insertHTML(_ html: String) {
            let escaped = html
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            webView?.evaluateJavaScript("insertHTML('\(escaped)')")
        }

        public func wrapSelectionWithLatex(display: Bool = false) {
            let open = display ? "\\\\[" : "\\\\("
            let close = display ? "\\\\]" : "\\\\)"
            let jsScript = """
            (function() {
                var sel = window.getSelection();
                if (sel.rangeCount > 0) {
                    var text = sel.toString() || 'x';
                    document.execCommand('insertHTML', false, '\(open)' + text + '\(close)');
                    window.webkit.messageHandlers.contentChanged.postMessage(editor.innerHTML);
                    typesetMath();
                }
            })()
            """
            webView?.evaluateJavaScript(jsScript)
        }
    }
}
