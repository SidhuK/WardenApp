
import Highlightr
import SwiftUI
import os

struct CodeView: View {
    let code: String
    let lang: String
    var isStreaming: Bool
    /// Filename named in the surrounding reply (e.g. `solve.py`), used as the Save… default.
    var suggestedFilename: String?
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
    @AppStorage("codeBlockShowLineNumbers") private var showLineNumbers = false
    @AppStorage("codeBlockWrapLines") private var wrapLines = true
    /// `nil` until the block is first shown finished: streaming blocks stay fully expanded until then.
    @State private var isExpanded: Bool?
    @State private var headerHeight: CGFloat = 0
    @State private var stickyHeaderOffset: CGFloat = 0

    /// Blocks with more lines than this start collapsed to this many lines of height.
    static let collapsedLineLimit = 25
    
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
    
    init(code: String, lang: String, isStreaming: Bool = false, suggestedFilename: String? = nil) {
        self.code = code
        self.lang = lang
        self.isStreaming = isStreaming
        self.suggestedFilename = suggestedFilename
        _isExpanded = State(initialValue: isStreaming ? nil : false)
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
    
    private var lineCount: Int {
        CodeBlockLines.count(in: code)
    }

    private var isCollapsible: Bool {
        lineCount > Self.collapsedLineLimit
    }

    private var isCollapsed: Bool {
        isCollapsible && isExpanded == false
    }

    private var displayedCode: NSAttributedString {
        if let highlighted = viewModel.highlightedCode {
            return highlighted
        }
        let font = NSFont(name: codeFont, size: chatFontSize - 1)
            ?? NSFont.monospacedSystemFont(ofSize: chatFontSize - 1, weight: .regular)
        return NSAttributedString(string: code, attributes: [.font: font, .foregroundColor: NSColor.textColor])
    }

    private var codeBlockView: some View {
        // The header is overlaid rather than stacked so it can be pushed down to stay visible while the top
        // of a tall block is scrolled out of view.
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear.frame(height: headerHeight)
                codeTextView
            }

            headerView
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    headerHeight = height
                }
                .overlay(alignment: .bottom) {
                    if stickyHeaderOffset > 0 {
                        Divider()
                    }
                }
                .offset(y: stickyHeaderOffset)
        }
        .onGeometryChange(for: CGFloat.self) { [headerHeight] proxy in
            let frame = proxy.frame(in: .scrollView)
            // Only stick for blocks that are tall enough that the header would otherwise be lost.
            guard headerHeight > 0, frame.height > headerHeight * 4 else { return 0 }
            return max(0, min(-frame.minY, frame.height - headerHeight * 2))
        } action: { offset in
            stickyHeaderOffset = offset
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
                #if DEBUG
                WardenLog.rendering.debug("Code changed during streaming: \(code.count, privacy: .public) char(s)")
                #endif
                updateHighlightedCode(colorScheme: colorScheme, code: code)
            }
        }
        .onChange(of: viewModel.highlightedCode) { _ in
            if !isRendered {
                isRendered = true
                NotificationCenter.default.post(
                    name: .codeBlockRendered,
                    object: nil
                )
            }
        }
        .onAppear {
            updateHighlightedCode(colorScheme: colorScheme)
        }
        .onChange(of: isStreaming) { streaming in
            // Collapse only once the reply has finished so streaming and auto-scroll are not disturbed,
            // and never override an explicit expand.
            if !streaming && isExpanded == nil {
                isExpanded = false
            }
        }
        .onChange(of: chatFontSize) { _ in
            Task { await HighlighterManager.shared.invalidateCache() }
            updateHighlightedCode(colorScheme: colorScheme)
        }
        .onChange(of: codeFont) { _ in
            Task { await HighlighterManager.shared.invalidateCache() }
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

    private var codeTextView: some View {
        // Extra room for the "Show all" button that overlays the bottom of a collapsed block.
        let collapsedTextHeight = CodeBlockTextView.lineHeight(for: displayedCode)
            * CGFloat(Self.collapsedLineLimit) + 28

        return VStack(spacing: 0) {
            CodeBlockTextView(
                attributedText: displayedCode,
                showLineNumbers: showLineNumbers,
                wrapLines: wrapLines,
                maxTextHeight: isCollapsed ? collapsedTextHeight : nil
            )
            .overlay(alignment: .bottom) {
                if isCollapsed {
                    collapsedFooter
                }
            }

            if isCollapsible && !isCollapsed && !isStreaming {
                expandedFooter
            }
        }
    }

    private var collapsedFooter: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [codeBackground.opacity(0), codeBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 56)
            .allowsHitTesting(false)

            Button(action: { setExpanded(true) }) {
                Label("Show all \(lineCount) lines", systemImage: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)
            .background(codeBackground)
        }
    }

    private var expandedFooter: some View {
        Button(action: { setExpanded(false) }) {
            Label("Show less", systemImage: "chevron.up")
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }

    private func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    private var lineCountLabel: String {
        lineCount == 1 ? "1 line" : "\(lineCount) lines"
    }

    private var headerView: some View {
        HStack(spacing: 8) {
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

            Text(lineCountLabel)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .monospacedDigit()
            
            Spacer()

            HStack(spacing: 4) {
                headerIconButton(
                    systemImage: "list.number",
                    label: showLineNumbers ? "Hide line numbers" : "Show line numbers",
                    isActive: showLineNumbers
                ) {
                    showLineNumbers.toggle()
                }
                headerIconButton(
                    systemImage: "arrow.turn.down.left",
                    label: wrapLines ? "Don't wrap long lines" : "Wrap long lines",
                    isActive: wrapLines
                ) {
                    wrapLines.toggle()
                }
                if isCollapsible && !isStreaming {
                    headerIconButton(
                        systemImage: isCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                        label: isCollapsed ? "Show all \(lineCount) lines" : "Collapse code block",
                        isActive: false
                    ) {
                        setExpanded(isCollapsed)
                    }
                }
                headerIconButton(systemImage: "square.and.arrow.down", label: "Save to file…", isActive: false) {
                    saveToFile()
                }
            }

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

    private func headerIconButton(
        systemImage: String,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? .accentColor : .secondary)
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = CodeBlockFile.suggestedName(suggestedFilename, language: lang)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let contents = CodeBlockFile.contents(of: code)

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(contents.utf8).write(to: url, options: .atomic)
            } catch {
                WardenLog.app.error("Failed to save code block: \(error.localizedDescription, privacy: .public)")
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
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

// MARK: - Line counting

enum CodeBlockLines {
    /// Number of lines shown for `code`. A single trailing newline does not start a new line.
    static func count(in code: String) -> Int {
        lineStarts(in: code as NSString).count
    }

    /// UTF-16 offsets where each line of `string` begins.
    static func lineStarts(in string: NSString) -> [Int] {
        var starts = [0]
        let length = string.length
        var index = 0
        while index < length {
            let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            let next = NSMaxRange(lineRange)
            guard next > index, next < length else { break }
            starts.append(next)
            index = next
        }
        return starts
    }
}

// MARK: - Saving

enum CodeBlockFile {
    private static let extensions: [String: String] = [
        "python": "py", "py": "py",
        "javascript": "js", "js": "js", "jsx": "jsx", "mjs": "mjs",
        "typescript": "ts", "ts": "ts", "tsx": "tsx",
        "swift": "swift",
        "html": "html", "xml": "xml", "svg": "svg",
        "css": "css", "scss": "scss", "sass": "sass", "less": "less",
        "json": "json", "jsonc": "json", "yaml": "yaml", "yml": "yml", "toml": "toml", "ini": "ini",
        "bash": "sh", "sh": "sh", "shell": "sh", "zsh": "zsh", "fish": "fish",
        "powershell": "ps1", "ps1": "ps1", "bat": "bat", "cmd": "bat",
        "markdown": "md", "md": "md",
        "c": "c", "h": "h", "cpp": "cpp", "c++": "cpp", "cc": "cpp", "hpp": "hpp",
        "objective-c": "m", "objc": "m", "objectivec": "m", "csharp": "cs", "c#": "cs", "cs": "cs",
        "java": "java", "kotlin": "kt", "kt": "kt", "scala": "scala", "groovy": "groovy",
        "go": "go", "golang": "go", "rust": "rs", "rs": "rs", "zig": "zig",
        "ruby": "rb", "rb": "rb", "php": "php", "perl": "pl", "lua": "lua", "r": "r",
        "dart": "dart", "elixir": "ex", "erlang": "erl", "haskell": "hs", "clojure": "clj",
        "sql": "sql", "graphql": "graphql", "dockerfile": "Dockerfile", "makefile": "mk",
        "vue": "vue", "svelte": "svelte", "tex": "tex", "latex": "tex", "diff": "diff", "csv": "csv",
        "text": "txt", "plaintext": "txt", "txt": "txt",
    ]

    static func suggestedName(_ suggestedFilename: String?, language: String) -> String {
        if let suggestedFilename {
            let name = (suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
                .lastPathComponent
            if !name.isEmpty {
                return name
            }
        }
        let ext = extensions[language.trimmingCharacters(in: .whitespaces).lowercased()] ?? "txt"
        return "snippet.\(ext)"
    }

    /// The parser drops the newline that ends a fenced block's last line, so restore it to save the block's
    /// exact content.
    static func contents(of code: String) -> String {
        code.isEmpty || code.hasSuffix("\n") ? code : code + "\n"
    }
}

// MARK: - Code text view

/// Selectable code text with an optional line-number gutter. The gutter is a separate view, so selecting
/// and copying text never includes line numbers. When wrapping is off, long lines scroll horizontally.
struct CodeBlockTextView: NSViewRepresentable {
    static let contentInsets = NSEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)

    let attributedText: NSAttributedString
    let showLineNumbers: Bool
    let wrapLines: Bool
    /// Clips the text to this height when set (used for collapsed blocks).
    let maxTextHeight: CGFloat?

    static func lineHeight(for attributedText: NSAttributedString) -> CGFloat {
        let font = CodeBlockTextContainerView.font(of: attributedText)
        return ceil(NSLayoutManager().defaultLineHeight(for: font))
    }

    func makeNSView(context: Context) -> CodeBlockTextContainerView {
        CodeBlockTextContainerView()
    }

    func updateNSView(_ nsView: CodeBlockTextContainerView, context: Context) {
        nsView.update(
            attributedText: attributedText,
            showLineNumbers: showLineNumbers,
            wrapLines: wrapLines,
            maxTextHeight: maxTextHeight
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CodeBlockTextContainerView, context: Context) -> CGSize? {
        let width = proposal.width ?? (nsView.bounds.width > 0 ? nsView.bounds.width : 400)
        return CGSize(width: width, height: nsView.fittingHeight(forWidth: width))
    }
}

final class CodeBlockTextContainerView: NSView {
    private let textView = NSTextView(frame: .zero)
    private let scrollView = CodeBlockHorizontalScrollView(frame: .zero)
    private let gutterView = CodeBlockLineNumberGutterView(frame: .zero)

    private var attributedText = NSAttributedString()
    private var showLineNumbers = false
    private var wrapLines = true
    private var maxTextHeight: CGFloat?

    private static let gutterSpacing: CGFloat = 12

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none

        gutterView.textView = textView

        addSubview(gutterView)
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func font(of attributedText: NSAttributedString) -> NSFont {
        if attributedText.length > 0,
           let font = attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    func update(attributedText: NSAttributedString, showLineNumbers: Bool, wrapLines: Bool, maxTextHeight: CGFloat?) {
        if attributedText !== self.attributedText && !attributedText.isEqual(to: self.attributedText) {
            self.attributedText = attributedText
            textView.textStorage?.setAttributedString(attributedText)
            gutterView.update(lineStarts: CodeBlockLines.lineStarts(in: attributedText.string as NSString),
                              font: Self.font(of: attributedText))
        }
        if wrapLines != self.wrapLines {
            self.wrapLines = wrapLines
            scrollView.contentView.scroll(to: .zero)
        }
        self.showLineNumbers = showLineNumbers
        self.maxTextHeight = maxTextHeight
        gutterView.isHidden = !showLineNumbers
        scrollView.hasHorizontalScroller = !wrapLines
        scrollView.allowsHorizontalScrolling = !wrapLines
        needsLayout = true
        gutterView.needsDisplay = true
    }

    private struct Metrics {
        var gutterWidth: CGFloat
        var textX: CGFloat
        var textWidth: CGFloat
        var documentWidth: CGFloat
        var textHeight: CGFloat
        var visibleTextHeight: CGFloat
    }

    private func metrics(forWidth width: CGFloat) -> Metrics {
        let insets = Self.contentInsetsValue
        let gutterWidth = showLineNumbers ? gutterView.requiredWidth : 0
        let textX = insets.left + (showLineNumbers ? gutterWidth + Self.gutterSpacing : 0)
        let textWidth = max(width - textX - insets.right, 20)

        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            return Metrics(gutterWidth: gutterWidth, textX: textX, textWidth: textWidth, documentWidth: textWidth,
                           textHeight: 0, visibleTextHeight: 0)
        }

        let containerWidth = wrapLines ? textWidth : CGFloat.greatestFiniteMagnitude
        if container.size.width != containerWidth {
            container.size = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let textHeight = max(ceil(used.height), CodeBlockTextView.lineHeight(for: attributedText))
        let documentWidth = wrapLines ? textWidth : max(textWidth, ceil(used.width))
        let visibleTextHeight = maxTextHeight.map { min(textHeight, $0) } ?? textHeight

        return Metrics(gutterWidth: gutterWidth, textX: textX, textWidth: textWidth, documentWidth: documentWidth,
                       textHeight: textHeight, visibleTextHeight: visibleTextHeight)
    }

    private static var contentInsetsValue: NSEdgeInsets { CodeBlockTextView.contentInsets }

    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        let insets = Self.contentInsetsValue
        let metrics = metrics(forWidth: width)
        // A collapsed block ends at the clip edge; its footer overlay supplies the bottom spacing.
        let bottom = maxTextHeight != nil && metrics.visibleTextHeight < metrics.textHeight ? 0 : insets.bottom
        return ceil(insets.top + metrics.visibleTextHeight + bottom)
    }

    override func layout() {
        super.layout()
        let insets = Self.contentInsetsValue
        let metrics = metrics(forWidth: bounds.width)

        // The scroll view is given the full text height and clipped by this view, so it never scrolls
        // vertically; vertical scrolling always belongs to the chat list.
        scrollView.frame = NSRect(x: metrics.textX, y: insets.top, width: metrics.textWidth,
                                  height: metrics.textHeight)
        textView.frame = NSRect(x: 0, y: 0, width: metrics.documentWidth, height: metrics.textHeight)
        gutterView.frame = NSRect(x: insets.left, y: insets.top, width: metrics.gutterWidth,
                                  height: metrics.textHeight)
        gutterView.needsDisplay = true
    }
}

/// Draws a line number beside the first line fragment of each logical line, so numbers stay aligned
/// when long lines wrap.
final class CodeBlockLineNumberGutterView: NSView {
    weak var textView: NSTextView?
    private var lineStarts: [Int] = [0]
    private var font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    override var isFlipped: Bool { true }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
    }

    var requiredWidth: CGFloat {
        let digits = max(String(lineStarts.count).count, 2)
        return ceil((String(repeating: "8", count: digits) as NSString).size(withAttributes: attributes).width)
    }

    func update(lineStarts: [Int], font: NSFont) {
        self.lineStarts = lineStarts
        self.font = font
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let length = textView.textStorage?.length ?? 0
        let attributes = attributes
        layoutManager.ensureLayout(for: textContainer)

        for (index, start) in lineStarts.enumerated() {
            let fragment: NSRect
            if start < length {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: start)
                fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            } else {
                fragment = layoutManager.extraLineFragmentRect
            }
            if fragment.minY > dirtyRect.maxY { break }
            guard fragment.maxY >= dirtyRect.minY else { continue }

            let number = String(index + 1) as NSString
            let size = number.size(withAttributes: attributes)
            number.draw(at: NSPoint(x: bounds.width - size.width, y: fragment.minY), withAttributes: attributes)
        }
    }
}

/// Scrolls horizontally only, handing vertical scroll gestures to the enclosing chat list.
final class CodeBlockHorizontalScrollView: NSScrollView {
    var allowsHorizontalScrolling = false
    private var forwardsCurrentGesture = true
    private var gestureAxisKnown = false

    override func scrollWheel(with event: NSEvent) {
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            gestureAxisKnown = false
            forwardsCurrentGesture = true
        }
        let isDiscrete = event.phase.isEmpty && event.momentumPhase.isEmpty
        // Latch the axis on the first movement so a gesture (and its momentum) stays with one scroll view.
        if (isDiscrete || !gestureAxisKnown) && (event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0) {
            forwardsCurrentGesture = !allowsHorizontalScrolling
                || abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            gestureAxisKnown = !isDiscrete
        }
        if forwardsCurrentGesture {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

#Preview {
    CodeView(code: "<h1>Hello World</h1>", lang: "html")
        .environmentObject(PreviewStateManager())
}
