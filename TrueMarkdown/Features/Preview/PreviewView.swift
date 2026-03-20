import SwiftUI
import WebKit

// MARK: - ZoomableWebView
//
// Subclasses WKWebView to clamp pinch-zoom in the NSResponder chain.
// Overriding magnify(with:) is the correct hook: it fires during the live
// trackpad gesture, below gesture recognizers, so there is zero conflict
// with WKWebView's internal pinch handling.

final class ZoomableWebView: WKWebView {
    let minZoom: CGFloat = 0.5
    let maxZoom: CGFloat = 3.0

    override func magnify(with event: NSEvent) {
        super.magnify(with: event) // native smooth zoom
        let clamped = min(max(magnification, minZoom), maxZoom)
        if magnification != clamped {
            let center = convert(event.locationInWindow, from: nil)
            setMagnification(clamped, centeredAt: center)
        }
    }
}

// MARK: - WeakScriptMessageProxy
//
// WKUserContentController retains its message handlers strongly.
// This proxy breaks the retain cycle that would keep the WKWebView alive.

final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}

// MARK: - PreviewView
//
// Design principle: self-contained. ContentView passes `htmlContent` as a plain String.
// The coordinator queues it and injects when the page is ready. No external callbacks.

struct PreviewView: NSViewRepresentable {
    /// Full pre-rendered HTML (with data-block-id wrappers).
    let htmlContent: String
    /// When set, the preview scrolls to this block ID (used by TOC).
    var scrollTarget: String?
    /// User selected font size from settings.
    var fontSize: Double = 15
    /// Called once the WKWebView is alive so ContentView can reference it for export.
    var onWebViewCreated: ((WKWebView) -> Void)? = nil

    // MARK: NSViewRepresentable

    func makeNSView(context: Context) -> ZoomableWebView {
        let config = WKWebViewConfiguration()
        // Register JS → native message handler for external links.
        // Using a weak proxy avoids retain cycle between WKUserContentController and Coordinator.
        let proxy = WeakScriptMessageProxy(target: context.coordinator)
        config.userContentController.add(proxy, name: "openExternal")

        let webView = ZoomableWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
        webView.navigationDelegate = context.coordinator

        // Prevent white flash while HTML template loads.
        // On macOS, isOpaque is get-only; use setValue(drawsBackground:) instead.
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = NSColor.clear

        context.coordinator.setup(webView: webView, initialHTML: htmlContent)
        onWebViewCreated?(webView)

        // Double-click resets zoom to 1×
        let doubleTap = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.resetZoom(_:))
        )
        doubleTap.numberOfClicksRequired = 2
        webView.addGestureRecognizer(doubleTap)

        return webView
    }

    func updateNSView(_ webView: ZoomableWebView, context: Context) {
        // Push new content whenever htmlContent changes
        context.coordinator.updateHTML(htmlContent, in: webView)
        // Push font size changes
        context.coordinator.updateFontSize(fontSize, in: webView)

        // Scroll to TOC target if set
        if let target = scrollTarget, target != context.coordinator.lastScrollTarget {
            context.coordinator.lastScrollTarget = target
            webView.evaluateJavaScript("scrollToBlock('\(target)'); null;", completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private(set) weak var webView: WKWebView?
        private var isPageReady = false
        private var pendingHTML: String?
        var lastHTML: String = "\u{200B}"  // sentinel so first update always fires
        var lastScrollTarget: String?
        var currentFontSize: Double = 0
        private var currentMagnification: CGFloat = 1.0

        func setup(webView: WKWebView, initialHTML: String) {
            self.webView = webView
            pendingHTML = initialHTML
            // Load the template from the bundle.
            // allowingReadAccessTo is set to the home directory so that local images
            // inserted into the document (e.g. from ~/Documents/assets/) can load.
            if let resourceDir = Bundle.main.resourceURL {
                let templateURL = resourceDir.appendingPathComponent("preview-template.html")
                if FileManager.default.fileExists(atPath: templateURL.path) {
                    let homeDir = URL(fileURLWithPath: NSHomeDirectory())
                    webView.loadFileURL(templateURL, allowingReadAccessTo: homeDir)
                    return
                }
            }
            // Fallback: use minimal inline template so the inject path still works
            webView.loadHTMLString(inlineTemplate, baseURL: Bundle.main.resourceURL)
        }

        func updateHTML(_ html: String, in webView: WKWebView) {
            guard html != lastHTML else { return }
            lastHTML = html
            if isPageReady {
                inject(html, into: webView)
            } else {
                pendingHTML = html
            }
        }
        
        func updateFontSize(_ size: Double, in webView: WKWebView) {
            guard size != currentFontSize else { return }
            currentFontSize = size
            if isPageReady {
                let js = "document.body.style.fontSize = '\(size)px';"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        private func inject(_ html: String, into webView: WKWebView) {
            // Dictionary JSON serialization perfectly escapes all HTML/JS characters
            // and avoids the "bare fragment" crash seen on some macOS versions.
            let payload = ["html": html]
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else {
                print("[True Markdown Preview] JSON encoding failed")
                return
            }
            // Suffix with `null;` so evaluateJavaScript returns null instead of a Promise,
            // avoiding the "unsupported type" error from WKWebView.
            webView.evaluateJavaScript("setFullContent(\(jsonStr).html); null;") { _, err in
                if let err { print("[True Markdown Preview] inject error:", err) }
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageReady = true
            // Restore saved zoom level after page reload
            webView.magnification = currentMagnification
            updateFontSize(currentFontSize, in: webView)
            if let html = pendingHTML {
                inject(html, into: webView)
                pendingHTML = nil
            }
        }


        // MARK: WKScriptMessageHandler — receive external link URLs from JS

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "openExternal",
                  let urlStr = message.body as? String,
                  let url = URL(string: urlStr) else { return }
            NSWorkspace.shared.open(url)
        }

        // MARK: WKNavigationDelegate

        /// Double-click resets zoom to 1×.
        @objc func resetZoom(_ gesture: NSClickGestureRecognizer) {
            guard let webView else { return }
            currentMagnification = 1.0
            webView.magnification = 1.0
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[True Markdown Preview] Navigation failed:", error.localizedDescription)
            // Fall back to inline template and retry
            webView.loadHTMLString(inlineTemplate, baseURL: Bundle.main.resourceURL)
        }

        // MARK: -- Navigation policy (open external links in system browser) --

        /// Legacy variant (macOS < 11). Intercepts any http/https navigation.
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url,
               url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// Modern variant (macOS 11+) — called preferentially on modern systems.
        @available(macOS 11.0, *)
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            if let url = action.request.url,
               url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel, preferences)
                return
            }
            decisionHandler(.allow, preferences)
        }

        // MARK: Minimal inline template (fallback when bundle file not found)

        private var inlineTemplate: String { """
        <!DOCTYPE html><html>
        <head><meta charset="UTF-8">
        <style>
        body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;
             font-size:15px;line-height:1.7;
             padding:32px 48px;max-width:860px;margin:0 auto;
             color:#1a1a1a;background:#fff;}
        @media(prefers-color-scheme:dark){body{color:#d4d4d4;background:#1e1e1e;}}
        h1,h2{border-bottom:1px solid #dde1e6;padding-bottom:.3em;}
        pre{background:#f5f5f5;padding:16px;border-radius:8px;overflow:auto;}
        code{font-family:Menlo,monospace;font-size:.875em;background:#f5f5f5;
             padding:.15em .35em;border-radius:4px;}
        table{border-collapse:collapse;width:100%;}
        th,td{padding:8px 12px;border:1px solid #ddd;}
        blockquote{border-left:4px solid #bbb;margin:1em 0;padding:.5em 1em;color:#555;}
        </style></head>
        <body>
        <div id="truemarkdown-content"></div>
        <script>
        function setFullContent(h){
            document.getElementById('truemarkdown-content').innerHTML=h;
        }
        function updateBlock(id,h){
            var e=document.querySelector('[data-block-id="'+id+'"]');
            if(e)e.outerHTML=h;
            else document.getElementById('truemarkdown-content').insertAdjacentHTML('beforeend',h);
        }
        function scrollToBlock(id){
            var e=document.querySelector('[data-block-id="'+id+'"],#'+id);
            if(e)e.scrollIntoView({behavior:'smooth'});
        }
        </script>
        </body></html>
        """ }
    }
}
