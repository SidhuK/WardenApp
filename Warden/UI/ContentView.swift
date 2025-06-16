import AppKit
import Combine
import CoreData
import Foundation
import SwiftUI

struct ContentView: View {
    @State private var window: NSWindow?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var store: ChatStore

    @FetchRequest(
        entity: ChatEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)],
        animation: .default
    )
    private var chats: FetchedResults<ChatEntity>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)])
    private var apiServices: FetchedResults<APIServiceEntity>

    @State var selectedChat: ChatEntity?
    @State var selectedProject: ProjectEntity?
    @AppStorage("gptToken") var gptToken = ""
    @AppStorage("gptModel") var gptModel = AppConstants.chatGptDefaultModel
    @AppStorage("lastOpenedChatId") var lastOpenedChatId = ""
    @AppStorage("apiUrl") var apiUrl = AppConstants.apiUrlChatCompletions
    @AppStorage("defaultApiService") private var defaultApiServiceID: String?
    @StateObject private var previewStateManager = PreviewStateManager()

    @State private var windowRef: NSWindow?
    @State private var openedChatId: String? = nil
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showingSettings = false
    
    // New state variables for inline project views
    @State private var showingCreateProject = false
    @State private var showingEditProject = false
    @State private var projectToEdit: ProjectEntity?

    var body: some View {
        NavigationSplitView {
            ChatListView(
                selectedChat: $selectedChat,
                selectedProject: $selectedProject,
                showingSettings: $showingSettings,
                showingCreateProject: $showingCreateProject,
                showingEditProject: $showingEditProject,
                projectToEdit: $projectToEdit,
                onNewChat: newChat,
                onOpenPreferences: openPreferencesView
            )
                .navigationSplitViewColumnWidth(
                    min: 180,
                    ideal: 220,
                    max: 400
                )
        } detail: {
            HSplitView {
                if showingSettings {
                    // Show settings in main content area
                    InlinePreferencesView()
                        .frame(minWidth: 400)
                } else if showingCreateProject {
                    // Show create project view inline
                    CreateProjectView(
                        onProjectCreated: { project in
                            selectedProject = project
                            showingCreateProject = false
                        },
                        onCancel: {
                            showingCreateProject = false
                        }
                    )
                    .frame(minWidth: 400)
                } else if showingEditProject, let project = projectToEdit {
                    // Show edit project view inline
                    ProjectSettingsView(project: project, onComplete: {
                        showingEditProject = false
                        projectToEdit = nil
                    })
                    .frame(minWidth: 400)
                } else if let project = selectedProject {
                    // Show project summary when project is selected
                    ProjectSummaryView(project: project)
                        .frame(minWidth: 400)
                } else if selectedChat != nil {
                    ChatView(viewContext: viewContext, chat: selectedChat!)
                        .frame(minWidth: 400)
                        .id(openedChatId)
                }
                else {
                    WelcomeScreen(
                        chatsCount: chats.count,
                        apiServiceIsPresent: apiServices.count > 0,
                        customUrl: apiUrl != AppConstants.apiUrlChatCompletions,
                        openPreferencesView: openPreferencesView,
                        newChat: newChat
                    )
                }

                if previewStateManager.isPreviewVisible && !showingSettings && selectedProject == nil {
                    PreviewPane(stateManager: previewStateManager)
                }
            }
        }
        .onAppear(perform: {
            if let lastOpenedChatId = UUID(uuidString: lastOpenedChatId) {
                if let lastOpenedChat = chats.first(where: { $0.id == lastOpenedChatId }) {
                    selectedChat = lastOpenedChat
                }
            }
        })
        .background(WindowAccessor(window: $window))
        .onAppear {
            NotificationCenter.default.addObserver(
                forName: AppConstants.newChatNotification,
                object: nil,
                queue: .main
            ) { notification in
                let windowId = window?.windowNumber
                if let sourceWindowId = notification.userInfo?["windowId"] as? Int,
                    sourceWindowId == windowId
                {
                    newChat()
                }
            }
            
            NotificationCenter.default.addObserver(
                forName: AppConstants.openInlineSettingsNotification,
                object: nil,
                queue: .main
            ) { notification in
                let windowId = window?.windowNumber
                if let sourceWindowId = notification.userInfo?["windowId"] as? Int,
                    sourceWindowId == windowId
                {
                    openPreferencesView()
                }
            }
            
            // Handle Spotlight search result selection
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("SelectChatFromSpotlight"),
                object: nil,
                queue: .main
            ) { notification in
                if let chat = notification.object as? ChatEntity {
                    selectedChat = chat
                    showingSettings = false // Close settings if open
                }
            }
            
            // Handle chat selection from project summary
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("SelectChatFromProjectSummary"),
                object: nil,
                queue: .main
            ) { notification in
                if let chat = notification.object as? ChatEntity {
                    selectedChat = chat
                    showingSettings = false // Close settings if open
                }
            }
        }
        .navigationTitle("")
        .onChange(of: scenePhase) { phase in
            print("Scene phase changed: \(phase)")
            if phase == .inactive {
                print("Saving state...")
            }
        }
        .onChange(of: selectedChat) { oldValue, newValue in
            if self.openedChatId != newValue?.id.uuidString {
                self.openedChatId = newValue?.id.uuidString
                previewStateManager.hidePreview()
            }
            // Close settings and clear project selection when selecting a chat
            if newValue != nil {
                showingSettings = false
                selectedProject = nil
            }
        }
        .onChange(of: selectedProject) { oldValue, newValue in
            // Clear chat selection and close settings when selecting a project
            if newValue != nil {
                selectedChat = nil
                showingSettings = false
                previewStateManager.hidePreview()
            }
        }
        .onChange(of: showingSettings) { oldValue, newValue in
            // Hide preview when showing settings
            if newValue {
                previewStateManager.hidePreview()
                // Clear both selections when opening settings
                selectedChat = nil
                selectedProject = nil
            }
        }
        .environmentObject(previewStateManager)
        .overlay(alignment: .top) {
            ToastManager()
        }
    }

    func newChat() {
        let uuid = UUID()
        let newChat = ChatEntity(context: viewContext)

        newChat.id = uuid
        newChat.newChat = true
        newChat.temperature = 0.8
        newChat.top_p = 1.0
        newChat.behavior = "default"
        newChat.newMessage = ""
        newChat.createdDate = Date()
        newChat.updatedDate = Date()
        newChat.systemMessage = AppConstants.chatGptSystemMessage
        newChat.gptModel = gptModel
        newChat.name = "New Chat"

        if let defaultServiceIDString = defaultApiServiceID,
            let url = URL(string: defaultServiceIDString),
            let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url)
        {

            do {
                let defaultService = try viewContext.existingObject(with: objectID) as? APIServiceEntity
                newChat.apiService = defaultService
                newChat.gptModel = defaultService?.model ?? AppConstants.chatGptDefaultModel
                
                // If the default API service has a default persona, use it
                if let defaultPersona = defaultService?.defaultPersona {
                    newChat.persona = defaultPersona
                    
                    // If the persona has its own preferred API service, use that instead
                    if let personaPreferredService = defaultPersona.defaultApiService {
                        newChat.apiService = personaPreferredService
                        newChat.gptModel = personaPreferredService.model ?? AppConstants.chatGptDefaultModel
                    }
                }
            }
            catch {
                print("Default API service not found: \(error)")
            }
        }

        do {
            try viewContext.save()
            
            // Index the new chat for Spotlight search
            store.indexChatForSpotlight(newChat)
            
            DispatchQueue.main.async {
                self.selectedChat?.objectWillChange.send()
                self.selectedChat = newChat
                // Close settings when creating new chat
                self.showingSettings = false
            }
        }
        catch {
            print("Error saving new chat: \(error.localizedDescription)")
            viewContext.rollback()
        }
    }

    func openPreferencesView() {
        showingSettings = true
        // Deselect current chat when opening settings
        selectedChat = nil
    }

    private func getIndex(for chat: ChatEntity) -> Int {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            return index
        }
        else {
            fatalError("Chat not found in array")
        }
    }
}

struct PreviewPane: View {
    @ObservedObject var stateManager: PreviewStateManager
    @State private var isResizing = false
    @State private var zoomLevel: Double = 1.0
    @State private var refreshTrigger = 0
    @State private var selectedDevice: DeviceType = .desktop
    @Environment(\.colorScheme) var colorScheme

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
            case .desktop: return (1024, 768)
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

    var body: some View {
        VStack(spacing: 0) {
            // Modern header with browser-like design
            modernHeader
            
            // Toolbar with controls
            toolbar
            
            Divider()
                .background(Color.gray.opacity(0.3))

            // HTML Preview content with device simulation
            ZStack {
                if selectedDevice == .desktop {
                    // Full-width desktop view
                    HTMLPreviewView(
                        htmlContent: enhancedHtmlContent, 
                        zoomLevel: zoomLevel,
                        refreshTrigger: refreshTrigger,
                        userAgent: selectedDevice.userAgent
                    )
                } else {
                    // Device frame simulation for mobile/tablet
                    deviceSimulationView
                }
            }
        }
        .background(modernBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .frame(minWidth: 320, maxWidth: 800)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if !isResizing {
                        isResizing = true
                    }
                    let newWidth = max(320, stateManager.previewPaneWidth - gesture.translation.width)
                    stateManager.previewPaneWidth = min(800, newWidth)
                }
                .onEnded { _ in
                    isResizing = false
                }
        )
    }
    
    private var deviceSimulationView: some View {
        VStack(spacing: 0) {
            // Device frame header (simulating browser chrome)
            deviceFrameHeader
            
            // Device viewport with proper scaling
            GeometryReader { geometry in
                let deviceDimensions = selectedDevice.dimensions
                let availableWidth = geometry.size.width - 40 // Account for padding
                let availableHeight = geometry.size.height - 80 // Account for frame elements
                
                let scaleToFit = min(
                    availableWidth / deviceDimensions.width,
                    availableHeight / deviceDimensions.height
                )
                
                let finalScale = min(scaleToFit, zoomLevel)
                
                VStack {
                    HTMLPreviewView(
                        htmlContent: enhancedHtmlContent,
                        zoomLevel: 1.0, // Handle scaling externally
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
                    .clipShape(RoundedRectangle(cornerRadius: selectedDevice == .mobile ? 25 : 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: selectedDevice == .mobile ? 25 : 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
        }
    }
    
    private var deviceFrameHeader: some View {
        HStack {
            // Device info
            HStack(spacing: 8) {
                Image(systemName: selectedDevice.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDevice.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("\(Int(selectedDevice.dimensions.width))×\(Int(selectedDevice.dimensions.height))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Device orientation toggle (for mobile/tablet)
            if selectedDevice != .desktop {
                Button(action: rotateDevice) {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color(red: 0.08, green: 0.08, blue: 0.1) : Color(red: 0.96, green: 0.96, blue: 0.98))
    }
    
    private var modernHeader: some View {
        HStack(spacing: 12) {
            // Beautiful title with icon
            HStack(spacing: 8) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                
                Text("HTML Preview")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                
                Text("Live")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Close button with modern styling
            Button(action: { stateManager.hidePreview() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .background(Color.clear)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                // Could add hover effect here if needed
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.17) : Color(red: 0.98, green: 0.98, blue: 0.99),
                    colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color(red: 0.96, green: 0.96, blue: 0.97)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var toolbar: some View {
        HStack(spacing: 12) {
            // Refresh button
            Button(action: refreshPreview) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .symbolEffect(.rotate.byLayer, options: .nonRepeating, value: refreshTrigger)
                    
                    Text("Refresh")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            Divider()
                .frame(height: 16)
            
            // Zoom controls
            HStack(spacing: 6) {
                Button(action: zoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(zoomLevel <= 0.5)
                
                Text("\(Int(zoomLevel * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 45)
                
                Button(action: zoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(zoomLevel >= 2.0)
            }
            
            Spacer()
            
            // Device selection menu
            Menu {
                ForEach(DeviceType.allCases, id: \.self) { device in
                    Button(action: {
                        selectedDevice = device
                        refreshTrigger += 1 // Refresh to apply new user agent
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
                HStack(spacing: 4) {
                    Image(systemName: selectedDevice.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(selectedDevice.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
            .menuStyle(BorderlessButtonMenuStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.12) : Color(red: 0.98, green: 0.98, blue: 0.99))
    }
    
    private var modernBackgroundColor: Color {
        colorScheme == .dark ? 
            Color(red: 0.12, green: 0.12, blue: 0.14) : 
            Color(red: 0.99, green: 0.99, blue: 1.0)
    }
    
    private var enhancedHtmlContent: String {
        // Inject modern CSS framework and styling with responsive meta tag
        let modernCSS = """
        <style>
        * {
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background: \(colorScheme == .dark ? "#1a1a1a" : "#ffffff");
            color: \(colorScheme == .dark ? "#e4e4e7" : "#1f2937");
            font-size: \(selectedDevice == .mobile ? "14px" : "16px");
        }
        
        h1, h2, h3, h4, h5, h6 {
            margin-top: 0;
            margin-bottom: 0.5em;
            font-weight: 600;
            line-height: 1.25;
        }
        
        h1 { font-size: \(selectedDevice == .mobile ? "1.8em" : "2.25em"); color: \(colorScheme == .dark ? "#f9fafb" : "#111827"); }
        h2 { font-size: \(selectedDevice == .mobile ? "1.5em" : "1.875em"); color: \(colorScheme == .dark ? "#f3f4f6" : "#1f2937"); }
        h3 { font-size: \(selectedDevice == .mobile ? "1.3em" : "1.5em"); color: \(colorScheme == .dark ? "#e5e7eb" : "#374151"); }
        
        p {
            margin-bottom: 1em;
        }
        
        a {
            color: \(colorScheme == .dark ? "#60a5fa" : "#2563eb");
            text-decoration: none;
            transition: color 0.2s ease;
        }
        
        a:hover {
            color: \(colorScheme == .dark ? "#93c5fd" : "#1d4ed8");
            text-decoration: underline;
        }
        
        code {
            background: \(colorScheme == .dark ? "#374151" : "#f3f4f6");
            padding: 2px 6px;
            border-radius: 4px;
            font-family: 'Fira Code', 'Monaco', 'Consolas', monospace;
            font-size: 0.9em;
        }
        
        pre {
            background: \(colorScheme == .dark ? "#1f2937" : "#f9fafb");
            border: 1px solid \(colorScheme == .dark ? "#374151" : "#e5e7eb");
            border-radius: 8px;
            padding: \(selectedDevice == .mobile ? "12px" : "16px");
            overflow-x: auto;
            margin: 1em 0;
            font-size: \(selectedDevice == .mobile ? "12px" : "14px");
        }
        
        pre code {
            background: none;
            padding: 0;
        }
        
        .container {
            max-width: \(selectedDevice == .mobile ? "100%" : selectedDevice == .tablet ? "90%" : "800px");
            margin: 0 auto;
            padding: 0 \(selectedDevice == .mobile ? "12px" : "16px");
        }
        
        .card {
            background: \(colorScheme == .dark ? "#374151" : "#ffffff");
            border: 1px solid \(colorScheme == .dark ? "#4b5563" : "#e5e7eb");
            border-radius: \(selectedDevice == .mobile ? "8px" : "12px");
            padding: \(selectedDevice == .mobile ? "16px" : "24px");
            margin: \(selectedDevice == .mobile ? "12px 0" : "16px 0");
            box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
        }
        
        button {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: \(selectedDevice == .mobile ? "10px 20px" : "12px 24px");
            border-radius: 8px;
            cursor: pointer;
            font-size: \(selectedDevice == .mobile ? "14px" : "16px");
            font-weight: 500;
            transition: all 0.2s ease;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
            width: \(selectedDevice == .mobile ? "100%" : "auto");
        }
        
        button:hover {
            transform: translateY(-1px);
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.15);
        }
        
        input, textarea, select {
            width: 100%;
            padding: \(selectedDevice == .mobile ? "14px" : "12px");
            border: 2px solid \(colorScheme == .dark ? "#4b5563" : "#e5e7eb");
            border-radius: 8px;
            background: \(colorScheme == .dark ? "#374151" : "#ffffff");
            color: \(colorScheme == .dark ? "#f9fafb" : "#1f2937");
            font-size: \(selectedDevice == .mobile ? "16px" : "14px"); /* Prevent zoom on iOS */
            transition: border-color 0.2s ease;
        }
        
        input:focus, textarea:focus, select:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 1em 0;
            font-size: \(selectedDevice == .mobile ? "12px" : "14px");
        }
        
        th, td {
            padding: \(selectedDevice == .mobile ? "8px" : "12px");
            text-align: left;
            border-bottom: 1px solid \(colorScheme == .dark ? "#4b5563" : "#e5e7eb");
        }
        
        th {
            background: \(colorScheme == .dark ? "#374151" : "#f9fafb");
            font-weight: 600;
        }
        
        .modern-gradient {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            font-weight: 700;
        }
        
        /* Responsive design specific to device type */
        @media (max-width: 768px) {
            body {
                padding: \(selectedDevice == .mobile ? "12px" : "16px");
            }
            
            .container {
                padding: 0 \(selectedDevice == .mobile ? "8px" : "12px");
            }
            
            .card {
                padding: \(selectedDevice == .mobile ? "12px" : "16px");
                margin: \(selectedDevice == .mobile ? "8px 0" : "12px 0");
            }
            
            h1 { font-size: 1.6em; }
            h2 { font-size: 1.4em; }
            h3 { font-size: 1.2em; }
        }
        
        /* Touch-friendly styles for mobile */
        \(selectedDevice == .mobile ? """
        @media (hover: none) and (pointer: coarse) {
            button, a, input, select, textarea {
                min-height: 44px; /* iOS accessibility guidelines */
            }
            
            button {
                font-size: 16px;
                padding: 14px 20px;
            }
        }
        """ : "")
        </style>
        """
        
        // Enhanced meta viewport for device simulation
        let viewportMeta = """
        <meta name="viewport" content="width=\(selectedDevice == .mobile ? "375" : selectedDevice == .tablet ? "768" : "1024"), initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        """
        
        // If the content already has HTML structure, inject our CSS and viewport
        if stateManager.previewContent.lowercased().contains("<html") || 
           stateManager.previewContent.lowercased().contains("<!doctype") {
            var modifiedContent = stateManager.previewContent
            
            // Add viewport meta tag
            if let headRange = modifiedContent.range(of: "<head>", options: .caseInsensitive) {
                let insertionPoint = modifiedContent.index(headRange.upperBound, offsetBy: 0)
                modifiedContent.insert(contentsOf: "\n    \(viewportMeta)", at: insertionPoint)
            }
            
            // Add CSS
            if let headEndRange = modifiedContent.range(of: "</head>", options: .caseInsensitive) {
                modifiedContent.insert(contentsOf: modernCSS, at: headEndRange.lowerBound)
            }
            
            return modifiedContent
        }
        
        // Otherwise, wrap content in full HTML structure
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            \(viewportMeta)
            <title>HTML Preview - \(selectedDevice.rawValue)</title>
            \(modernCSS)
        </head>
        <body>
            \(stateManager.previewContent)
        </body>
        </html>
        """
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
    
    private func rotateDevice() {
        // Swap width and height for device rotation
        let currentDimensions = selectedDevice.dimensions
        // Note: This is a simplified rotation - in a full implementation, 
        // we might want to track orientation state separately
        refreshTrigger += 1
    }
}

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
