import CoreData
import SwiftUI
import os

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
        MasterDetailLayout(masterWidth: 280) {
            // Sidebar
            VStack(spacing: 0) {
                GlassToolbar {
                    HStack {
                        Text("API Services")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Button(action: duplicateService) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.borderless)
                            .disabled(selectedServiceID == nil)
                            .help("Duplicate")
                            
                            Button(action: addNewService) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderless)
                            .help("Add Service")
                        }
                    }
                }
                
                if apiServices.isEmpty {
                    GlassEmptyState(
                        icon: "network",
                        title: "No Services",
                        subtitle: "Add an API service to get started"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(apiServices, id: \.objectID) { service in
                                GlassListRow(
                                    iconImage: "logo_\(service.type ?? "openai")",
                                    title: service.name ?? "Untitled",
                                    subtitle: service.model ?? "No model",
                                    isSelected: selectedServiceID == service.objectID,
                                    badge: service.objectID.uriRepresentation().absoluteString == defaultApiServiceID ? "Default" : nil,
                                    badgeColor: .blue
                                ) {
                                    selectedServiceID = service.objectID
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
        } detail: {
            if let service = selectedService {
                APIServiceDetailContent(
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
                .id(service.objectID)
            } else {
                GlassEmptyState(
                    icon: "network",
                    title: "Select a Service",
                    subtitle: "Choose an API service from the sidebar"
                )
            }
        }
        .onAppear {
            if selectedServiceID == nil && !apiServices.isEmpty {
                selectedServiceID = apiServices.first?.objectID
            }
        }
    }

    private func addNewService() {
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
            WardenLog.coreData.error("Error creating new service: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func duplicateService() {
        guard let selectedService = apiServices.first(where: { $0.objectID == selectedServiceID }) else { return }
        
        let newService = selectedService.copy() as! APIServiceEntity
        newService.name = (selectedService.name ?? "") + " Copy"
        newService.addedDate = Date()
        
        let newServiceID = UUID()
        newService.id = newServiceID

        if let oldServiceIDString = selectedService.id?.uuidString {
            do {
                if let token = try TokenManager.getToken(for: oldServiceIDString) {
                    try TokenManager.setToken(token, for: newServiceID.uuidString)
                }
            } catch {
                WardenLog.app.error("Error copying API token: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try viewContext.save()
            selectedServiceID = newService.objectID
            refreshList()
        } catch {
            WardenLog.coreData.error("Error duplicating service: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshList() {
        refreshID = UUID()
    }
}

// MARK: - Detail Content View
struct APIServiceDetailContent: View {
    @ObservedObject var service: APIServiceEntity
    let viewContext: NSManagedObjectContext
    let onDelete: () -> Void
    let onSetDefault: () -> Void
    let isDefault: Bool
    
    @StateObject private var viewModel: APIServiceDetailViewModel
    @State private var lampColor: Color = .gray
    @State private var showingDeleteConfirmation = false
    @FocusState private var isTokenFocused: Bool
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
        _viewModel = StateObject(wrappedValue: APIServiceDetailViewModel(viewContext: viewContext, apiService: service))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    Image("logo_\(service.type ?? "openai")")
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.primary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.name ?? "Untitled")
                            .font(.system(size: 20, weight: .semibold))
                        Text(AppConstants.defaultApiConfigurations[service.type ?? ""]?.name ?? "Unknown")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if isDefault {
                        StatusBadge(text: "Default", color: .blue)
                    } else {
                        Button("Set Default") { onSetDefault() }
                            .buttonStyle(.bordered)
                    }
                }
                
                // Basic Settings
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(title: "Basic Settings", icon: "slider.horizontal.3", iconColor: .blue)
                        
                        VStack(spacing: 12) {
                            SettingsRow(title: "Service Name") {
                                TextField("", text: $viewModel.name)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                            }
                            
                            SettingsDivider()
                            
                            SettingsRow(title: "API Type") {
                                HStack(spacing: 8) {
                                    Image("logo_\(viewModel.type)")
                                        .resizable()
                                        .renderingMode(.template)
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
                            }
                            
                            SettingsDivider()
                            
                            SettingsRow(title: "API URL") {
                                HStack(spacing: 8) {
                                    TextField("", text: $viewModel.url)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 250)
                                    
                                    Button("Reset") {
                                        viewModel.url = viewModel.defaultApiConfiguration?.url ?? ""
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 11))
                                }
                            }
                        }
                    }
                }
                
                // Authentication
                if (viewModel.defaultApiConfiguration?.apiKeyRef ?? "") != "" {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            SettingsSectionHeader(title: "Authentication", icon: "key.fill", iconColor: .orange)
                            
                            VStack(spacing: 12) {
                                SettingsRow(title: "API Token") {
                                    TextField("", text: $viewModel.apiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 250)
                                        .focused($isTokenFocused)
                                        .blur(radius: !viewModel.apiKey.isEmpty && !isTokenFocused ? 3 : 0)
                                        .onChange(of: viewModel.apiKey) { _, newValue in
                                            viewModel.onChangeApiKey(newValue)
                                        }
                                }
                                
                                if let apiKeyRef = viewModel.defaultApiConfiguration?.apiKeyRef,
                                   let url = URL(string: apiKeyRef) {
                                    HStack {
                                        Spacer()
                                        Link("Get API Token", destination: url)
                                            .font(.system(size: 11))
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Model Selection
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(title: "Model", icon: "brain", iconColor: .purple)
                        
                        VStack(spacing: 12) {
                            SettingsRow(title: "LLM Model") {
                                HStack(spacing: 8) {
                                    Picker("", selection: $viewModel.selectedModel) {
                                        ForEach(viewModel.availableModels.sorted(), id: \.self) { model in
                                            Text(model).tag(model)
                                        }
                                        Text("Custom...").tag("custom")
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 200)
                                    .labelsHidden()
                                    .disabled(viewModel.isLoadingModels)
                                    .onChange(of: viewModel.selectedModel) { _, newValue in
                                        viewModel.isCustomModel = newValue == "custom"
                                        if newValue != "custom" {
                                            viewModel.model = newValue
                                        }
                                    }
                                    
                                    if AppConstants.defaultApiConfigurations[viewModel.type]?.modelsFetching ?? false {
                                        ButtonWithStatusIndicator(
                                            title: "Refresh",
                                            action: { viewModel.onUpdateModelsList() },
                                            isLoading: viewModel.isLoadingModels,
                                            hasError: viewModel.modelFetchError != nil,
                                            errorMessage: "Can't fetch models",
                                            successMessage: "Click to refresh",
                                            isSuccess: !viewModel.isLoadingModels && viewModel.modelFetchError == nil && viewModel.availableModels.count > 0
                                        )
                                    }
                                }
                            }
                            
                            if viewModel.isCustomModel {
                                SettingsRow(title: "Custom Model") {
                                    TextField("Model name", text: $viewModel.model)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 200)
                                }
                            }
                            
                            if let apiModelRef = viewModel.defaultApiConfiguration?.apiModelRef,
                               let url = URL(string: apiModelRef) {
                                HStack {
                                    Spacer()
                                    Link("Models Reference", destination: url)
                                        .font(.system(size: 11))
                                }
                            }
                            
                            SettingsDivider()
                            
                            HStack {
                                Text("Test Connection")
                                    .font(.system(size: 13))
                                Spacer()
                                ButtonTestApiTokenAndModel(
                                    lampColor: $lampColor,
                                    gptToken: viewModel.apiKey,
                                    gptModel: viewModel.model,
                                    apiUrl: viewModel.url,
                                    apiType: viewModel.type
                                )
                            }
                        }
                    }
                }
                
                // Model Visibility
                if !viewModel.fetchedModels.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            SettingsSectionHeader(title: "Model Visibility", icon: "eye", iconColor: .cyan)
                            
                            ModelSelectionView(
                                serviceType: viewModel.type,
                                availableModels: viewModel.fetchedModels,
                                onSelectionChanged: { selectedIds in
                                    viewModel.updateSelectedModels(selectedIds)
                                }
                            )
                        }
                    }
                }
                
                // Context & Features
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(title: "Behavior", icon: "gearshape.2.fill", iconColor: .gray)
                        
                        VStack(spacing: 12) {
                            SettingsRow(
                                title: "Context Size",
                                subtitle: "Number of messages to include"
                            ) {
                                HStack(spacing: 8) {
                                    Slider(value: $viewModel.contextSize, in: 5...100, step: 5)
                                        .frame(width: 120)
                                    Text("\(Int(viewModel.contextSize))")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 30)
                                }
                            }
                            
                            SettingsDivider()
                            
                            SettingsRow(
                                title: "Auto Chat Naming",
                                subtitle: "Generate names from content"
                            ) {
                                Toggle("", isOn: $viewModel.generateChatNames)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                            
                            SettingsDivider()
                            
                            SettingsRow(
                                title: "Stream Responses",
                                subtitle: "Show text as it's generated"
                            ) {
                                Toggle("", isOn: $viewModel.useStreamResponse)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                            
                            if viewModel.supportsImageUploads {
                                SettingsDivider()
                                
                                SettingsRow(
                                    title: "Image Uploads",
                                    subtitle: "Enable vision capabilities"
                                ) {
                                    Toggle("", isOn: $viewModel.imageUploadsAllowed)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                }
                            }
                        }
                    }
                }
                
                // Default Assistant
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(title: "Default Assistant", icon: "person.fill", iconColor: .green)
                        
                        Picker("", selection: $viewModel.defaultAiPersona) {
                            ForEach(personas) { persona in
                                Text(persona.name ?? "Untitled").tag(persona)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                        .labelsHidden()
                    }
                }
                
                // Reasoning Model Warning
                if AppConstants.openAiReasoningModels.contains(viewModel.model) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Reasoning models don't support system messages. Temperature is fixed at 1.0.")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                    )
                }
                
                // Actions
                HStack {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button {
                        viewModel.saveAPIService()
                    } label: {
                        Label("Save Changes", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                
                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .alert("Delete Service", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteAPIService()
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this service?")
        }
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

#Preview {
    TabAPIServicesView()
        .frame(width: 800, height: 600)
}
