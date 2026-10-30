import SwiftUI
import WebKit

/// Renders feed HTML with JavaScript off; links open in the default browser.
struct HTMLView: View {
    let html: String
    let baseURL: URL?

    var body: some View {
        WebView(document: Self.document(html), baseURL: baseURL)
    }

    static func document(_ body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>
          body { font: -apple-system-body; font-family: -apple-system, "Hiragino Sans", sans-serif; line-height: 1.75;
                 margin: 0; padding: 0 2px 48px; color: CanvasText; background: transparent; overflow-wrap: anywhere; }
          img, video, iframe { max-width: 100%; height: auto; }
          pre { overflow-x: auto; padding: 12px; background: rgba(127,127,127,.12); border-radius: 8px; }
          blockquote { margin: 0; padding-left: 12px; border-left: 3px solid rgba(127,127,127,.35); color: GrayText; }
          a { color: LinkText; }
        </style></head><body>\(body)</body></html>
        """
    }
}

private final class Coordinator: NSObject, WKNavigationDelegate {
    var lastDocument = ""

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        await UIApplication.shared.open(url)
        #endif
        return .cancel
    }
}

private func makeWebView(_ coordinator: Coordinator) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(frame: .zero, configuration: config)
    view.navigationDelegate = coordinator
    #if os(iOS)
    view.isOpaque = false
    view.backgroundColor = .clear
    #else
    view.setValue(false, forKey: "drawsBackground")
    #endif
    return view
}

private func load(_ view: WKWebView, _ coordinator: Coordinator, _ document: String, _ baseURL: URL?) {
    guard coordinator.lastDocument != document else { return }
    coordinator.lastDocument = document
    view.loadHTMLString(document, baseURL: baseURL)
}

#if os(macOS)
private struct WebView: NSViewRepresentable {
    let document: String
    let baseURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { load(view, context.coordinator, document, baseURL) }
}
#else
private struct WebView: UIViewRepresentable {
    let document: String
    let baseURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { load(view, context.coordinator, document, baseURL) }
}
#endif
