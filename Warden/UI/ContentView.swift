import AppKit
import Combine
import CoreData
import Foundation
import SwiftUI
import os

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
    
    // New state variables for inline project views
    @State private var showingCreateProject = false
    @State private var showingEditProject = false
    @State private var projectToEdit: ProjectEntity?

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
                .ignoresSafeArea()

            NavigationSplitView {
                sidebarContent
            } detail: {
                detailView
            }
        }
        .onAppear(perform: setupInitialState)
        .background(WindowAccessor(window: $window))
        .navigationTitle("")
        .onChange(of: scenePhase) { _, newValue in
            setupScenePhaseChange(phase: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.newChatNotification)) { notification in
            let windowId = window?.windowNumber
            if let sourceWindowId = notification.userInfo?["windowId"] as? Int,
                sourceWindowId == windowId
            {
                newChat()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.createNewProjectNotification)) { _ in
            showingCreateProject = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SelectChatFromProjectSummary"))) { notification in
            if let chat = notification.object as? ChatEntity {
                selectedChat = chat
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenChatByID"))) { notification in
            if let objectID = notification.userInfo?["chatObjectID"] as? NSManagedObjectID {
                if let chat = viewContext.object(with: objectID) as? ChatEntity {
                    DispatchQueue.main.async {
                        selectedChat = chat
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenInlineSettings"))) { _ in
            SettingsWindowManager.shared.openSettingsWindow()
        }
        .onChange(of: selectedChat) { oldValue, newValue in
            setupSelectedChatChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: selectedProject) { oldValue, newValue in
            setupSelectedProjectChange(oldValue: oldValue, newValue: newValue)
        }
        .environmentObject(previewStateManager)
        .overlay(alignment: .top) {
            ToastManager()
        }
    }

    private var sidebarContent: some View {
        ChatListView(
            selectedChat: $selectedChat,
            selectedProject: $selectedProject,
            showingCreateProject: $showingCreateProject,
            showingEditProject: $showingEditProject,
            projectToEdit: $projectToEdit,
            onNewChat: newChat,
            onOpenPreferences: {
                SettingsWindowManager.shared.openSettingsWindow()
            }
        )
        .navigationSplitViewColumnWidth(
            min: 180,
            ideal: 220,
            max: 400
        )
    }

    private func setupInitialState() {
        if let lastOpenedChatId = UUID(uuidString: lastOpenedChatId) {
            if let lastOpenedChat = chats.first(where: { $0.id == lastOpenedChatId }) {
                selectedChat = lastOpenedChat
            }
        }
    }

    private func setupScenePhaseChange(phase: ScenePhase) {
        #if DEBUG
        WardenLog.app.debug("Scene phase changed: \(String(describing: phase), privacy: .public)")
        #endif
        if phase == .inactive {
            #if DEBUG
            WardenLog.app.debug("Saving state...")
            #endif
        }
    }

    private func setupSelectedChatChange(oldValue: ChatEntity?, newValue: ChatEntity?) {
        if self.openedChatId != newValue?.id.uuidString {
            self.openedChatId = newValue?.id.uuidString
            previewStateManager.hidePreview()
        }
        if newValue != nil {
            selectedProject = nil
        }
    }

    private func setupSelectedProjectChange(oldValue: ProjectEntity?, newValue: ProjectEntity?) {
        if newValue != nil {
            selectedChat = nil
            previewStateManager.hidePreview()
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
                WardenLog.coreData.error("Default API service not found: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try viewContext.save()
            
            // Select the new chat
            selectedChat = newChat
        }
        catch {
            WardenLog.coreData.error("Error saving new chat: \(error.localizedDescription, privacy: .public)")
            viewContext.rollback()
        }
    }

    func openSettings() {
        SettingsWindowManager.shared.openSettingsWindow()
    }

    private func getIndex(for chat: ChatEntity) -> Int {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            return index
        }
        else {
            #if DEBUG
            WardenLog.app.debug("Chat not found in array, returning 0")
            #endif
            return 0
        }
    }
    
    private var detailView: some View {
        HSplitView {
            if showingCreateProject {
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
                    openPreferencesView: openSettings,
                    newChat: newChat
                )
            }

            if previewStateManager.isPreviewVisible && selectedProject == nil {
                PreviewPane(stateManager: previewStateManager)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
            }
        }
        .overlay(
            Rectangle()
                .fill(AppConstants.borderSubtle)
                .frame(width: 1),
            alignment: .leading
        )
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
                        htmlContent: PreviewHTMLGenerator.generate(
                            content: stateManager.previewContent,
                            colorScheme: colorScheme,
                            device: selectedDevice
                        ), 
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
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                        htmlContent: PreviewHTMLGenerator.generate(
                            content: stateManager.previewContent,
                            colorScheme: colorScheme,
                            device: selectedDevice
                        ),
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
            Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.6) : 
            Color(red: 0.99, green: 0.99, blue: 1.0).opacity(0.6)
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
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.styleMask.insert(.fullSizeContentView)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}
