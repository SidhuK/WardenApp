
import SwiftUI
@preconcurrency
import WebKit
import os

struct HTMLPreviewView: View {
    let htmlContent: String
    let zoomLevel: Double
    let refreshTrigger: Int
    let userAgent: String?
    @State private var isLoading = true
    @Environment(\.colorScheme) var colorScheme
    
    // Default initializer for backward compatibility
    init(htmlContent: String) {
        self.htmlContent = htmlContent
        self.zoomLevel = 1.0
        self.refreshTrigger = 0
        self.userAgent = nil
    }
    
    // Enhanced initializer with zoom and refresh
    init(htmlContent: String, zoomLevel: Double, refreshTrigger: Int) {
        self.htmlContent = htmlContent
        self.zoomLevel = zoomLevel
        self.refreshTrigger = refreshTrigger
        self.userAgent = nil
    }
    
    // Full initializer with user agent support
    init(htmlContent: String, zoomLevel: Double, refreshTrigger: Int, userAgent: String?) {
        self.htmlContent = htmlContent
        self.zoomLevel = zoomLevel
        self.refreshTrigger = refreshTrigger
        self.userAgent = userAgent
    }
    
    var body: some View {
        ZStack {
            WebViewWrapper(
                htmlContent: htmlContent, 
                zoomLevel: zoomLevel,
                refreshTrigger: refreshTrigger,
                userAgent: userAgent,
                isLoading: $isLoading
            )
            
            if isLoading {
                modernLoadingView
            }
        }
    }
    
    private var modernLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.2)
            
            Text("Loading Preview...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            colorScheme == .dark ? 
                Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.95) : 
                Color.white.opacity(0.95)
        )
        .transition(.opacity)
    }
}

struct WebViewWrapper: NSViewRepresentable {
    let htmlContent: String
    let zoomLevel: Double
    let refreshTrigger: Int
    let userAgent: String?
    @Binding var isLoading: Bool
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Set custom user agent if provided
        if let userAgent = userAgent {
            configuration.applicationNameForUserAgent = userAgent
        }
        
        // Disable context menu for cleaner experience
        configuration.preferences.setValue(false, forKey: "developerExtrasEnabled")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        
        // Set custom user agent directly on webView if provided
        if let userAgent = userAgent {
            webView.customUserAgent = userAgent
        }
        
        // Apply modern styling
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 8
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Update user agent if it changed
        if let userAgent = userAgent, webView.customUserAgent != userAgent {
            webView.customUserAgent = userAgent
        }
        
        // Check if content changed or refresh was triggered
        let shouldReload = context.coordinator.lastContent != htmlContent || 
                          context.coordinator.lastRefreshTrigger != refreshTrigger ||
                          context.coordinator.lastUserAgent != userAgent
        
        if shouldReload {
            context.coordinator.lastContent = htmlContent
            context.coordinator.lastRefreshTrigger = refreshTrigger
            context.coordinator.lastUserAgent = userAgent
            isLoading = true
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
        
        // Apply zoom level
        if abs(webView.magnification - zoomLevel) > 0.01 {
            webView.setMagnification(zoomLevel, centeredAt: CGPoint(x: webView.bounds.midX, y: webView.bounds.midY))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewWrapper
        var lastContent: String = ""
        var lastRefreshTrigger: Int = 0
        var lastUserAgent: String? = nil
        
        init(parent: WebViewWrapper) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.parent.isLoading = false
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            WardenLog.app.error("WebView navigation failed: \(error.localizedDescription, privacy: .public)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            WardenLog.app.error("WebView provisional navigation failed: \(error.localizedDescription, privacy: .public)")
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigation for now - could add restrictions for security
            decisionHandler(.allow)
        }
    }
}
