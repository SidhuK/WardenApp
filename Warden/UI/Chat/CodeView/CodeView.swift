
import AttributedText
import Highlightr
import SwiftUI

struct CodeView: View {
    let code: String
    let lang: String
    var isStreaming: Bool
    @StateObject private var viewModel: CodeViewModel
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var previewStateManager: PreviewStateManager
    @State private var isRendered = false
    @State private var showInlinePreview = false
    @State private var selectedDevice: DeviceType = .desktop
    @State private var zoomLevel: Double = 1.0
    @State private var refreshTrigger = 0
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    @AppStorage("codeFont") private var codeFont: String = AppConstants.firaCode
    
    enum DeviceType: String, CaseIterable {
        case desktop = "Desktop"
        case tablet = "Tablet"
        case mobile = "Mobile"
        
        var icon: String {
            switch self {
            case .desktop: return "laptopcomputer"
            case .tablet: return "ipad"
            case .mobile: return "iphone"
            }
        }
        
        var dimensions: (width: CGFloat, height: CGFloat) {
            switch self {
            case .desktop: return (800, 600)
            case .tablet: return (768, 1024)
            case .mobile: return (375, 667)
            }
        }
        
        var userAgent: String {
            switch self {
            case .desktop: return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            case .tablet: return "Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
            case .mobile: return "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
            }
        }
    }
    
    init(code: String, lang: String, isStreaming: Bool = false) {
        self.code = code
        self.lang = lang
        self.isStreaming = isStreaming
        _viewModel = StateObject(
            wrappedValue: CodeViewModel(
                code: code,
                language: lang,
                isStreaming: isStreaming
            )
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Code block
            codeBlockView
            
            // Inline HTML preview
            if showInlinePreview && lang.lowercased() == "html" {
                inlinePreviewView
            }
        }
        .animation(nil, value: code)
    }
    
    private var codeBlockView: some View {
        VStack(spacing: 0) {
            headerView
            
            if let highlighted = viewModel.highlightedCode {
                AttributedText(highlighted)
                    .textSelection(.enabled)
                    .padding([.horizontal, .bottom], 16)
                    .padding(.top, 12)
            }
            else {
                Text(code)
                    .textSelection(.enabled)
                    .padding([.horizontal, .bottom], 16)
                    .padding(.top, 12)
                    .font(.custom(codeFont, size: chatFontSize - 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: showInlinePreview ? 12 : 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12.0)
                .stroke(colorScheme == .dark ? 
                    Color.white.opacity(0.1) : Color.black.opacity(0.1), 
                    lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        .onChange(of: colorScheme) { newScheme in
            updateHighlightedCode(colorScheme: newScheme)
        }
        .onChange(of: code) { code in
            if isStreaming {
                print("Code changed: \(code)")
                updateHighlightedCode(colorScheme: colorScheme, code: code)
            }
        }
        .onChange(of: viewModel.highlightedCode) { _ in
            if !isRendered {
                isRendered = true
                NotificationCenter.default.post(
                    name: NSNotification.Name("CodeBlockRendered"),
                    object: nil
                )
            }
        }
        .onAppear {
            updateHighlightedCode(colorScheme: colorScheme)
        }
        .onChange(of: chatFontSize) { _ in
            HighlighterManager.shared.invalidateCache()
            updateHighlightedCode(colorScheme: colorScheme)
        }
        .onChange(of: codeFont) { _ in
            HighlighterManager.shared.invalidateCache()
            updateHighlightedCode(colorScheme: colorScheme)
        }
    }
    
    private var inlinePreviewView: some View {
        VStack(spacing: 0) {
            // Preview header
            previewHeader
            
            // Preview content
            if selectedDevice == .desktop {
                // Full-width desktop preview
                HTMLPreviewView(
                    htmlContent: enhancedHtmlContent,
                    zoomLevel: zoomLevel,
                    refreshTrigger: refreshTrigger,
                    userAgent: selectedDevice.userAgent
                )
                .frame(height: 400)
            } else {
                // Device simulation view
                deviceSimulationView
            }
        }
        .background(previewBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? 
                    Color.white.opacity(0.1) : Color.black.opacity(0.1), 
                    lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
        .padding(.top, 8)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)).combined(with: .offset(y: -10)),
            removal: .opacity.combined(with: .scale(scale: 0.95))
        ))
        .animation(.easeInOut(duration: 0.3), value: showInlinePreview)
    }
    
    private var previewHeader: some View {
        HStack(spacing: 12) {
            // Preview title
            HStack(spacing: 8) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                
                Text("HTML Preview")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Controls
            HStack(spacing: 8) {
                // Refresh button
                Button(action: refreshPreview) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .symbolEffect(.rotate.byLayer, options: .nonRepeating, value: refreshTrigger)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Zoom controls
                HStack(spacing: 4) {
                    Button(action: zoomOut) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(zoomLevel <= 0.5)
                    
                    Text("\(Int(zoomLevel * 100))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 35)
                    
                    Button(action: zoomIn) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(zoomLevel >= 2.0)
                }
                
                // Device selector
                Menu {
                    ForEach(DeviceType.allCases, id: \.self) { device in
                        Button(action: {
                            selectedDevice = device
                            refreshTrigger += 1
                        }) {
                            HStack {
                                Image(systemName: device.icon)
                                Text(device.rawValue)
                                if selectedDevice == device {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: selectedDevice.icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                
                // Close preview button
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showInlinePreview = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(colorScheme == .dark ? 
                    Color(red: 0.1, green: 0.1, blue: 0.12) : 
                    Color(red: 0.96, green: 0.96, blue: 0.98)
                )
        )
    }
    
    private var deviceSimulationView: some View {
        GeometryReader { geometry in
            let deviceDimensions = selectedDevice.dimensions
            let availableWidth = geometry.size.width - 40
            let availableHeight = geometry.size.height - 40
            
            let scaleToFit = min(
                availableWidth / deviceDimensions.width,
                availableHeight / deviceDimensions.height
            )
            
            let finalScale = min(scaleToFit, zoomLevel * 0.8) // Slightly smaller for inline view
            
            VStack {
                HTMLPreviewView(
                    htmlContent: enhancedHtmlContent,
                    zoomLevel: 1.0,
                    refreshTrigger: refreshTrigger,
                    userAgent: selectedDevice.userAgent
                )
                .frame(
                    width: deviceDimensions.width,
                    height: deviceDimensions.height
                )
                .scaleEffect(finalScale)
                .clipped()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: selectedDevice == .mobile ? 20 : 8))
                .overlay(
                    RoundedRectangle(cornerRadius: selectedDevice == .mobile ? 20 : 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 450)
        .padding(20)
    }

    private var headerView: some View {
        HStack {
            if lang != "" {
                HStack(spacing: 6) {
                    // Language icon/badge
                    Image(systemName: getLanguageIcon(for: lang))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                    
                    Text(lang.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
                )
            }
            
            Spacer()

            HStack(spacing: 8) {
                if lang.lowercased() == "html" {
                    runButton
                }
                copyButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(colorScheme == .dark ? 
                    Color(red: 0.12, green: 0.12, blue: 0.14) : 
                    Color(red: 0.94, green: 0.94, blue: 0.96)
                )
        )
    }

    private func getLanguageIcon(for language: String) -> String {
        switch language.lowercased() {
        case "html": return "globe"
        case "css": return "paintbrush"
        case "javascript", "js": return "bolt"
        case "python": return "snake"
        case "swift": return "bird"
        case "java": return "cup.and.saucer"
        case "c", "c++", "cpp": return "cpu"
        case "sql": return "cylinder"
        case "json": return "curlybraces"
        case "xml": return "doc.text"
        case "yaml", "yml": return "list.bullet"
        case "bash", "shell": return "terminal"
        case "php": return "server.rack"
        case "ruby": return "gem"
        case "go": return "speedometer"
        case "rust": return "gear"
        case "typescript", "ts": return "t.square"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private var copyButton: some View {
        Button(action: viewModel.copyToClipboard) {
            HStack(spacing: 4) {
                Image(systemName: viewModel.isCopied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                    .font(.system(size: 12, weight: .medium))
                    .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: viewModel.isCopied)
                
                Text(viewModel.isCopied ? "Copied" : "Copy")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(viewModel.isCopied ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(viewModel.isCopied ? 
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green.opacity(0.7), Color.green.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        ) :
                        LinearGradient(
                            gradient: Gradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.15)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(viewModel.isCopied ? 
                        Color.green.opacity(0.3) : Color.gray.opacity(0.2), 
                        lineWidth: 0.5)
            )
            .shadow(color: viewModel.isCopied ? 
                Color.green.opacity(0.2) : Color.clear, 
                radius: 1, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: viewModel.isCopied)
    }

    private var runButton: some View {
        Button(action: togglePreview) {
            HStack(spacing: 4) {
                Image(systemName: showInlinePreview ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: showInlinePreview)
                
                Text(showInlinePreview ? "Stop" : "Run")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: showInlinePreview ? 
                        [Color.red.opacity(0.8), Color.red.opacity(0.9)] :
                        [Color.green.opacity(0.7), Color.green.opacity(0.8)]
                    ),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(showInlinePreview ? 
                        Color.red.opacity(0.3) : Color.green.opacity(0.3), 
                        lineWidth: 0.5)
            )
            .shadow(color: showInlinePreview ? 
                Color.red.opacity(0.2) : Color.green.opacity(0.2), 
                radius: 1, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(1.0)
        .animation(.easeInOut(duration: 0.15), value: showInlinePreview)
    }

    private func togglePreview() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showInlinePreview.toggle()
        }
        
        // Also hide the side panel if it's open
        if previewStateManager.isPreviewVisible {
            previewStateManager.hidePreview()
        }
    }
    
    private var enhancedHtmlContent: String {
        // Enhanced CSS with device-specific optimizations
        let modernCSS = AppConstants.getModernCSS(
            isMobile: selectedDevice == .mobile,
            isTablet: selectedDevice == .tablet,
            isDark: colorScheme == .dark
        )
        
        let viewportMeta = AppConstants.viewportMeta
        
        if code.lowercased().contains("<html") || code.lowercased().contains("<!doctype") {
            var modifiedContent = code
            
            if let headRange = modifiedContent.range(of: "<head>", options: .caseInsensitive) {
                let insertionPoint = modifiedContent.index(headRange.upperBound, offsetBy: 0)
                modifiedContent.insert(contentsOf: "\n    \(viewportMeta)", at: insertionPoint)
            }
            
            if let headEndRange = modifiedContent.range(of: "</head>", options: .caseInsensitive) {
                modifiedContent.insert(contentsOf: modernCSS, at: headEndRange.lowerBound)
            }
            
            return modifiedContent
        }
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            \(viewportMeta)
            <title>HTML Preview</title>
            \(modernCSS)
        </head>
        <body>
            \(code)
        </body>
        </html>
        """
    }

    private var codeBackground: Color {
        colorScheme == .dark ? 
            Color(red: 0.16, green: 0.16, blue: 0.18) : 
            Color(red: 0.97, green: 0.97, blue: 0.98)
    }
    
    private var previewBackground: Color {
        colorScheme == .dark ? 
            Color(red: 0.14, green: 0.14, blue: 0.16) : 
            Color(red: 0.99, green: 0.99, blue: 1.0)
    }

    private func updateHighlightedCode(colorScheme: ColorScheme, code: String = "") {
        DispatchQueue.main.async {
            if code != "" {
                viewModel.code = code
            }
            viewModel.updateHighlighting(colorScheme: colorScheme)
        }
    }
    
    private func refreshPreview() {
        refreshTrigger += 1
    }
    
    private func zoomIn() {
        if zoomLevel < 2.0 {
            zoomLevel += 0.25
        }
    }
    
    private func zoomOut() {
        if zoomLevel > 0.5 {
            zoomLevel -= 0.25
        }
    }
}

#Preview {
    CodeView(code: "<h1>Hello World</h1>", lang: "html")
        .environmentObject(PreviewStateManager())
}
