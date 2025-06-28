import CoreData
import SwiftUI


struct TabAPIServicesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    @State private var selectedServiceID: NSManagedObjectID?
    @State private var refreshID = UUID()
    @AppStorage("defaultApiService") private var defaultApiServiceID: String?

    private var isSelectedServiceDefault: Bool {
        guard let selectedServiceID = selectedServiceID else { return false }
        return selectedServiceID.uriRepresentation().absoluteString == defaultApiServiceID
    }
    
    private var selectedService: APIServiceEntity? {
        guard let selectedServiceID = selectedServiceID else { return nil }
        return apiServices.first(where: { $0.objectID == selectedServiceID })
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar - API Services List
            VStack(spacing: 0) {
                // Sidebar Header
                HStack {
                    Text("API Services")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))

                        Divider()

                // Services List
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(apiServices, id: \.objectID) { service in
                            APIServiceSidebarRow(
                                service: service,
                                isSelected: selectedServiceID == service.objectID,
                                isDefault: service.objectID.uriRepresentation().absoluteString == defaultApiServiceID
                            ) {
                                selectedServiceID = service.objectID
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Divider()
                
                // Bottom Actions
                HStack(spacing: 12) {
                    Button(action: addNewService) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                                    }
                    .buttonStyle(.borderless)
                    .help("Add New Service")
                    
                    Button(action: duplicateService) {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 14, weight: .medium))
                            }
                    .buttonStyle(.borderless)
                    .disabled(selectedServiceID == nil)
                    .help("Duplicate Service")
                    
                    Spacer()
            }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(width: 250)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Right Side - Service Details
            Group {
                if let service = selectedService {
                    APIServiceInlineDetailView(
                        service: service,
                        viewContext: viewContext,
                        onDelete: {
                            selectedServiceID = nil
                            refreshList()
                        },
                        onSetDefault: {
                            defaultApiServiceID = service.objectID.uriRepresentation().absoluteString
                        },
                        isDefault: isSelectedServiceDefault
                    )
                    .id(service.objectID) // Force SwiftUI to recreate the view when service changes
                } else {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "network")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("Select an API Service")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Choose a service from the sidebar to view and edit its settings")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            // Select first service if none selected
            if selectedServiceID == nil && !apiServices.isEmpty {
                selectedServiceID = apiServices.first?.objectID
                }
        }
    }

    private func addNewService() {
        // Create a new service and select it
        let newService = APIServiceEntity(context: viewContext)
        newService.id = UUID()
        newService.name = "New API Service"
        newService.type = "openai"
        newService.url = URL(string: AppConstants.defaultApiConfigurations["openai"]?.url ?? "")
        newService.model = "gpt-4o"
        newService.contextSize = 20
        newService.generateChatNames = true
        newService.useStreamResponse = true
        newService.imageUploadsAllowed = false
        newService.addedDate = Date()
        
        do {
            try viewContext.save()
            selectedServiceID = newService.objectID
            refreshList()
        } catch {
            print("Error creating new service: \(error)")
        }
    }

    private func duplicateService() {
        guard let selectedService = apiServices.first(where: { $0.objectID == selectedServiceID }) else { return }
        
            let newService = selectedService.copy() as! APIServiceEntity
            newService.name = (selectedService.name ?? "") + " Copy"
            newService.addedDate = Date()

            // Generate new UUID and copy the token
            let newServiceID = UUID()
            newService.id = newServiceID

            if let oldServiceIDString = selectedService.id?.uuidString {
                do {
                    if let token = try TokenManager.getToken(for: oldServiceIDString) {
                        try TokenManager.setToken(token, for: newServiceID.uuidString)
                    }
                }
                catch {
                    print("Error copying API token: \(error)")
                }
            }

            do {
                try viewContext.save()
            selectedServiceID = newService.objectID
                refreshList()
            }
            catch {
                print("Error duplicating service: \(error)")
            }
        }

    private func refreshList() {
        refreshID = UUID()
    }
}

// MARK: - Sidebar Row Component
struct APIServiceSidebarRow: View {
    let service: APIServiceEntity
    let isSelected: Bool
    let isDefault: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Service Icon
                Image("logo_\(service.type ?? "openai")")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(service.name ?? "Untitled Service")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if isDefault {
                            Text("DEFAULT")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                    }
                    
                    Text(service.model ?? "No model")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 3)
                    .animation(.easeInOut(duration: 0.2), value: isSelected),
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
    }
    }
    
// MARK: - Inline Detail View Component  
struct APIServiceInlineDetailView: View {
    @ObservedObject var service: APIServiceEntity
    let viewContext: NSManagedObjectContext
    let onDelete: () -> Void
    let onSetDefault: () -> Void
    let isDefault: Bool
    
    @StateObject private var viewModel: APIServiceDetailViewModel
    @State private var lampColor: Color = .gray
    @State private var showingDeleteConfirmation: Bool = false
    @FocusState private var isFocused: Bool
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)],
        animation: .default
    )
    private var personas: FetchedResults<PersonaEntity>
    
    private let types = AppConstants.apiTypes

    init(service: APIServiceEntity, viewContext: NSManagedObjectContext, onDelete: @escaping () -> Void, onSetDefault: @escaping () -> Void, isDefault: Bool) {
        self.service = service
        self.viewContext = viewContext
        self.onDelete = onDelete
        self.onSetDefault = onSetDefault
        self.isDefault = isDefault
        
        let viewModel = APIServiceDetailViewModel(viewContext: viewContext, apiService: service)
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with title and default button
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 12) {
                            Image("logo_\(service.type ?? "openai")")
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 24, height: 24)
                                .foregroundColor(.primary)
            
                            Text(service.name ?? "Untitled Service")
                .font(.title2)
                .fontWeight(.semibold)
                        }
                        
                        Text(AppConstants.defaultApiConfigurations[service.type ?? ""]?.name ?? "Unknown Type")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if !isDefault {
                        Button("Set as Default") {
                            onSetDefault()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    } else {
                        Text("DEFAULT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .cornerRadius(6)
                    }
                }
                
                Divider()
                
                // Settings in two-column layout like General settings
                VStack(spacing: 20) {
                    // Service Name
                    HStack {
                        Text("Service Name:")
                            .frame(width: 140, alignment: .leading)
                        
                        TextField("API Name", text: $viewModel.name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Spacer()
                    }
                    
                    // API Type
                    HStack {
                        Text("API Type:")
                            .frame(width: 140, alignment: .leading)
                        
                        HStack(spacing: 8) {
                            Image("logo_\(viewModel.type)")
                                .resizable()
                                .renderingMode(.template)
                                .interpolation(.high)
                                .antialiased(true)
                                .frame(width: 14, height: 14)

                            Picker("", selection: $viewModel.type) {
                                ForEach(types, id: \.self) {
                                    Text(AppConstants.defaultApiConfigurations[$0]?.name ?? $0)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                            .labelsHidden()
                            .onChange(of: viewModel.type) { _, newValue in
                                viewModel.onChangeApiType(newValue)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    // API URL
                    HStack {
                        Text("API URL:")
                            .frame(width: 140, alignment: .leading)
                        
                        TextField("Paste your URL here", text: $viewModel.url)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button("Default") {
                            viewModel.url = viewModel.defaultApiConfiguration?.url ?? ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Spacer()
                    }
                    
                    // API Token (if required)
                    if (viewModel.defaultApiConfiguration?.apiKeyRef ?? "") != "" {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("API Token:")
                                    .frame(width: 140, alignment: .leading)
                                
                                TextField("Paste your token here", text: $viewModel.apiKey)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .focused($isFocused)
                                    .blur(radius: !viewModel.apiKey.isEmpty && !isFocused ? 3 : 0.0, opaque: false)
                                    .onChange(of: viewModel.apiKey) { _, newValue in
                                        viewModel.onChangeApiKey(newValue)
                                    }
                                
                                Spacer()
                            }
                            
                            if let apiKeyRef = viewModel.defaultApiConfiguration?.apiKeyRef,
                               let url = URL(string: apiKeyRef) {
                                HStack {
                                    Spacer()
                                    Link(
                                        "How to get API Token",
                                        destination: url
                                    )
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                }
                                .padding(.leading, 140)
                            }
                        }
                    }
                    
                    // LLM Model
                    HStack {
                        Text("LLM Model:")
                            .frame(width: 140, alignment: .leading)
                        
                        HStack(spacing: 8) {
                            Picker("", selection: $viewModel.selectedModel) {
                                ForEach(viewModel.availableModels.sorted(), id: \.self) { modelName in
                                    Text(modelName).tag(modelName)
                                }
                                Text("Enter custom model").tag("custom")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                            .labelsHidden()
                            .onChange(of: viewModel.selectedModel) { _, newValue in
                                if newValue == "custom" {
                                    viewModel.isCustomModel = true
                                }
                                else {
                                    viewModel.isCustomModel = false
                                    viewModel.model = newValue
                                }
                            }
                            .disabled(viewModel.isLoadingModels)

                            if AppConstants.defaultApiConfigurations[viewModel.type]?.modelsFetching ?? false {
                                ButtonWithStatusIndicator(
                                    title: "Update",
                                    action: { viewModel.onUpdateModelsList() },
                                    isLoading: viewModel.isLoadingModels,
                                    hasError: viewModel.modelFetchError != nil,
                                    errorMessage: "Can't get models from server",
                                    successMessage: "Click to refresh models list",
                                    isSuccess: !viewModel.isLoadingModels && viewModel.modelFetchError == nil && viewModel.availableModels.count > 0
                                )
                            }
                        }
                        
                        Spacer()
                    }
                    
                    // Custom Model Input (if needed)
                    if viewModel.isCustomModel {
                        HStack {
                            Text("")
                                .frame(width: 140, alignment: .leading)
                            
                            TextField("Enter custom model name", text: $viewModel.model)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Spacer()
                        }
                    }
                    
                    // Model Reference Link
                    if let apiModelRef = viewModel.defaultApiConfiguration?.apiModelRef,
                       let url = URL(string: apiModelRef) {
                        HStack {
                            Text("")
                                .frame(width: 140, alignment: .leading)
                            
                            HStack {
                                Link(
                                    "Models reference",
                                    destination: url
                                )
                                .font(.caption)
                                .foregroundColor(.blue)
                                
                                Spacer()
                            }
                            
                            Spacer()
                        }
                    }
                    
                    // Test API Button
                    HStack {
                        Text("")
                            .frame(width: 140, alignment: .leading)
                        
                        ButtonTestApiTokenAndModel(
                            lampColor: $lampColor,
                            gptToken: viewModel.apiKey,
                            gptModel: viewModel.model,
                            apiUrl: viewModel.url,
                            apiType: viewModel.type
                        )
                
            Spacer()
        }
                }
                
                Divider()
                
                // Model Selection Configuration (if available)
                if !viewModel.fetchedModels.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Model Visibility")
                            .font(.headline)
                        
                        ModelSelectionView(
                            serviceType: viewModel.type,
                            availableModels: viewModel.fetchedModels,
                            onSelectionChanged: { selectedIds in
                                viewModel.updateSelectedModels(selectedIds)
                            }
                        )
                    }
                    
                    Divider()
                }
                
                // Context Size
                VStack(alignment: .leading, spacing: 12) {
                    Text("Context Configuration")
                        .font(.headline)
                    
                    HStack {
                        Text("Context Size:")
                            .frame(width: 140, alignment: .leading)
                        
                        HStack {
                            Slider(
                                value: $viewModel.contextSize,
                                in: 5...100,
                                step: 5
                            )
                            .frame(width: 200)
                            
                            Text("\(Int(viewModel.contextSize)) messages")
                                .frame(width: 100, alignment: .leading)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                Divider()
                
                // Feature Toggles
                VStack(alignment: .leading, spacing: 12) {
                    Text("Features")
                        .font(.headline)
                    
                    VStack(spacing: 16) {
                        HStack {
                            Text("Auto Chat Naming:")
                                .frame(width: 140, alignment: .leading)
                            
                            Picker("", selection: $viewModel.generateChatNames) {
                                Text("Disabled").tag(false)
                                Text("Enabled").tag(true)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                            .labelsHidden()
                            
                            Button(action: {}) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Chat name will be generated based on chat messages using the selected model")
                            
                            Spacer()
                        }
                        
                        HStack {
                            Text("Stream Responses:")
                                .frame(width: 140, alignment: .leading)
                            
                            Picker("", selection: $viewModel.useStreamResponse) {
                                Text("Disabled").tag(false)
                                Text("Enabled").tag(true)
    }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                            .labelsHidden()
                            
                            Button(action: {}) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Enable real-time streaming of responses instead of waiting for completion")
                            
                            Spacer()
                        }
                        
                        if viewModel.supportsImageUploads {
                            HStack {
                                Text("Image Uploads:")
                                    .frame(width: 140, alignment: .leading)
                                
                                Picker("", selection: $viewModel.imageUploadsAllowed) {
                                    Text("Disabled").tag(false)
                                    Text("Enabled").tag(true)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                                .labelsHidden()
                                
                                Button(action: {}) {
                                    Image(systemName: "questionmark.circle")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Allow image uploads for vision-capable models")
                                
                                Spacer()
                            }
                        }
                    }
                }
                
                Divider()
                
                // Default AI Assistant
                HStack {
                    Text("Default Assistant:")
                        .frame(width: 140, alignment: .leading)
                    
                    Picker("", selection: $viewModel.defaultAiPersona) {
                        ForEach(personas) { persona in
                            Text(persona.name ?? "Untitled").tag(persona)
                        }
        }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                    .labelsHidden()
                    
                    Spacer()
                }
                
                // Reasoning Model Warning
                if AppConstants.openAiReasoningModels.contains(viewModel.model) {
                    Text("💁‍♂️ OpenAI API doesn't support system message and temperature other than 1 for o1 models. Warden will send system message as a user message internally, while temperature will be always set to 1.0")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Divider()
                
                // Bottom Actions
                HStack {
                    Button("Delete Service") {
                        showingDeleteConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    
                    Spacer()
                    
                    Button("Save Changes") {
                        viewModel.saveAPIService()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete API Service"),
                message: Text("Are you sure you want to delete this API Service? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    viewModel.deleteAPIService()
                    onDelete()
                },
                secondaryButton: .cancel()
        )
        }
    }
}

// MARK: - Inline Version for Main Window (keeping the existing structure for compatibility)
struct InlineTabAPIServicesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    @State private var isShowingAddOrEditService = false
    @State private var selectedServiceID: NSManagedObjectID?
    @State private var refreshID = UUID()
    @AppStorage("defaultApiService") private var defaultApiServiceID: String?

    // Colors matching the chat app theme
    private let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    private var cardBackgroundColor: Color {
        Color(NSColor.controlBackgroundColor)
    }

    private var isSelectedServiceDefault: Bool {
        guard let selectedServiceID = selectedServiceID else { return false }
        return selectedServiceID.uriRepresentation().absoluteString == defaultApiServiceID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "network", title: "API Services")
            
            settingGroup {
                VStack(spacing: 16) {
                    entityListView
                        .id(refreshID)
                        .frame(minHeight: 260)

                    Divider()

                    HStack(spacing: 20) {
                        if selectedServiceID != nil {
                            Button(action: onEdit) {
                                Label("Edit", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .keyboardShortcut(.defaultAction)

                            Button(action: onDuplicate) {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)

                            if !isSelectedServiceDefault {
                                Button(action: {
                                    defaultApiServiceID = selectedServiceID?.uriRepresentation().absoluteString
                                }) {
                                    Label("Set as Default", systemImage: "star")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                            }
                            Spacer()
                        }
                        else {
                            Spacer()
                        }
                        Button(action: onAdd) {
                            Label("Add New Service", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAddOrEditService) {
            let selectedApiService = apiServices.first(where: { $0.objectID == selectedServiceID }) ?? nil
            if selectedApiService == nil {
                APIServiceDetailView(viewContext: viewContext, apiService: nil)
            }
            else {
                APIServiceDetailView(viewContext: viewContext, apiService: selectedApiService)
            }
        }
    }

    private var entityListView: some View {
        EntityListView(
            selectedEntityID: $selectedServiceID,
            entities: apiServices,
            detailContent: detailContent,
            onRefresh: refreshList,
            getEntityColor: { _ in nil },
            getEntityName: { $0.name ?? "Untitled Service" },
            getEntityDefault: { $0.objectID.uriRepresentation().absoluteString == defaultApiServiceID },
            getEntityIcon: { "logo_" + ($0.type ?? "") },
            onEdit: {
                if selectedServiceID != nil {
                    isShowingAddOrEditService = true
                }
            },
            onMove: nil
        )
    }

    private func detailContent(service: APIServiceEntity?) -> some View {
        Group {
            if let service = service {
                VStack(alignment: .leading, spacing: 10) {
                    detailRow(label: "Type", value: AppConstants.defaultApiConfigurations[service.type!]?.name ?? "Unknown")
                    detailRow(label: "Model", value: service.model ?? "Not specified")
                    detailRow(label: "Context Size", value: "\(service.contextSize)")
                    detailRow(label: "Auto Chat Naming", value: service.generateChatNames ? "Enabled" : "Disabled")
                    detailRow(label: "Default Assistant", value: service.defaultPersona?.name ?? "None")
                }
                .padding(10)
            }
            else {
                Text("Select an API service to view details")
                    .foregroundColor(.secondary)
                    .font(.callout)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
            }
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    private func refreshList() {
        refreshID = UUID()
    }

    private func onAdd() {
        selectedServiceID = nil
        isShowingAddOrEditService = true
    }

    private func onDuplicate() {
        if let selectedService = apiServices.first(where: { $0.objectID == selectedServiceID }) {
            let newService = selectedService.copy() as! APIServiceEntity
            newService.name = (selectedService.name ?? "") + " Copy"
            newService.addedDate = Date()

            // Generate new UUID and copy the token
            let newServiceID = UUID()
            newService.id = newServiceID

            if let oldServiceIDString = selectedService.id?.uuidString {
                do {
                    if let token = try TokenManager.getToken(for: oldServiceIDString) {
                        try TokenManager.setToken(token, for: newServiceID.uuidString)
                    }
                }
                catch {
                    print("Error copying API token: \(error)")
                }
            }

            do {
                try viewContext.save()
                refreshList()
            }
            catch {
                print("Error duplicating service: \(error)")
            }
        }
    }

    private func onEdit() {
        isShowingAddOrEditService = true
    }
    
    // MARK: - Section Header Style
    private func sectionHeader(icon: String, title: String, iconColor: Color? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(iconColor ?? primaryBlue)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Setting Group Style
    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

struct APIServiceRowView: View {
    let service: APIServiceEntity

    var body: some View {
        VStack(alignment: .leading) {
            Text(service.name ?? "Untitled Service")
                .font(.headline)
            Text(service.type ?? "Unknown type")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
