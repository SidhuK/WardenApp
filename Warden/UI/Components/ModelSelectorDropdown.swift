import SwiftUI
import CoreData
import Combine

// ViewModel to handle heavy lifting of sorting and filtering
@MainActor
final class ModelSelectorViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var filteredSections: [ModelSection] = []
    
    // Data sources
    private let modelCache = ModelCacheManager.shared
    private let selectedModelsManager = SelectedModelsManager.shared
    private let favoriteManager = FavoriteModelsManager.shared
    
    private var apiServices: [APIServiceEntity] = []
    private var cancellables = Set<AnyCancellable>()
    
    struct ModelSection: Identifiable {
        let id: String
        let title: String
        let items: [ModelItem]
    }
    
    struct ModelItem: Identifiable, Equatable {
        let id: String // "provider_modelId"
        let provider: String
        let modelId: String
        let isFavorite: Bool
        
        static func == (lhs: ModelItem, rhs: ModelItem) -> Bool {
            return lhs.id == rhs.id && lhs.isFavorite == rhs.isFavorite
        }
    }
    
    init() {
        // Observe changes that should trigger a refresh
        favoriteManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshData() }
            .store(in: &cancellables)
            
        // Debounce search to avoid rapid re-calculations
        $searchText
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshData() }
            .store(in: &cancellables)
    }
    
    func updateServices(_ services: [APIServiceEntity]) {
        self.apiServices = services
        refreshData()
    }
    
    func refreshData() {
        // Perform heavy calculation on background thread if needed, 
        // but for now just doing it efficiently is enough.
        
        let availableModels = getAvailableModels()
        var sections: [ModelSection] = []
        
        // 1. Favorites
        if searchText.isEmpty {
            let favorites = getFavorites(from: availableModels)
            if !favorites.isEmpty {
                sections.append(ModelSection(id: "favorites", title: "Favorites", items: favorites))
            }
        } else {
            sections.append(ModelSection(id: "search", title: "Search Results", items: []))
        }
        
        // 2. All Models (Filtered)
        let filtered = getFilteredModels(from: availableModels)
        
        // If searching, we just show one flat list in the "Search Results" section usually, 
        // or we can keep provider sections. The original code kept provider sections.
        // Let's stick to the original design: Provider sections.
        
        // However, for the "All Models" part, we need to exclude favs if not searching
        let favIds = Set(sections.first(where: { $0.id == "favorites" })?.items.map { $0.id } ?? [])
        let excludeIds = favIds
        
        var providerSections: [ModelSection] = []
        
        for (provider, models) in filtered {
            let items = models.compactMap { modelId -> ModelItem? in
                let uniqueId = "\(provider)_\(modelId)"
                if searchText.isEmpty && excludeIds.contains(uniqueId) {
                    return nil
                }
                return ModelItem(
                    id: uniqueId,
                    provider: provider,
                    modelId: modelId,
                    isFavorite: favoriteManager.isFavorite(provider: provider, model: modelId)
                )
            }
            
            if !items.isEmpty {
                providerSections.append(ModelSection(id: provider, title: getProviderDisplayName(provider), items: items))
            }
        }
        
        // So we just append the provider sections to the main list
        sections.append(contentsOf: providerSections)
        
        filteredSections = sections
    }
    
    private func getAvailableModels() -> [(provider: String, models: [String])] {
        var result: [(provider: String, models: [String])] = []
        
        for service in apiServices {
            guard let serviceType = service.type else { continue }
            let serviceModels = modelCache.getModels(for: serviceType)
            
            let visibleModels = serviceModels.filter { model in
                if selectedModelsManager.hasCustomSelection(for: serviceType) {
                    return selectedModelsManager.getSelectedModelIds(for: serviceType).contains(model.id)
                }
                return true
            }
            
            if !visibleModels.isEmpty {
                result.append((provider: serviceType, models: visibleModels.map { $0.id }))
            }
        }
        return result
    }
    
    private func getFilteredModels(from available: [(provider: String, models: [String])]) -> [(provider: String, models: [String])] {
        var modelsToFilter = available
        
        // Apply search
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            modelsToFilter = modelsToFilter.compactMap { provider, models in
                let filtered = models.filter { model in
                    model.lowercased().contains(searchLower) ||
                    provider.lowercased().contains(searchLower)
                }
                return filtered.isEmpty ? nil : (provider: provider, models: filtered)
            }
        }
        
        // Sort
        return modelsToFilter.map { provider, models in
            let sorted = models.sorted { first, second in
                // Simple alphabetical sort for the main list, 
                // as favorites are handled separately.
                return first < second
            }
            return (provider: provider, models: sorted)
        }
    }
    
    private func getFavorites(from available: [(provider: String, models: [String])]) -> [ModelItem] {
        var items: [ModelItem] = []
        for (provider, models) in available {
            for model in models {
                if favoriteManager.isFavorite(provider: provider, model: model) {
                    items.append(ModelItem(
                        id: "\(provider)_\(model)",
                        provider: provider,
                        modelId: model,
                        isFavorite: true
                    ))
                }
            }
        }
        return items
    }
    
    private func getProviderDisplayName(_ provider: String) -> String {
        switch provider {
        case "chatgpt": return "OpenAI"
        case "claude": return "Anthropic"
        case "gemini": return "Google"
        case "xai": return "xAI"
        case "perplexity": return "Perplexity"
        case "deepseek": return "DeepSeek"
        case "groq": return "Groq"
        case "openrouter": return "OpenRouter"
        case "ollama": return "Ollama"
        case "mistral": return "Mistral"
        default: return provider.capitalized
        }
    }
}

struct StandaloneModelSelector: View {
    @ObservedObject var chat: ChatEntity
    @Environment(\.managedObjectContext) private var viewContext
    
    // Use the ViewModel
    @StateObject private var viewModel = ModelSelectorViewModel()
    
    // Keep these for direct actions
    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    @StateObject private var metadataCache = ModelMetadataCache.shared
    
    @State private var hoveredItem: String? = nil
    
    var isExpanded: Bool = true
    var onDismiss: (() -> Void)? = nil
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    var body: some View {
        if isExpanded {
            popoverContent
                .environment(\.managedObjectContext, viewContext)
                .onAppear {
                    viewModel.updateServices(Array(apiServices))
                }
                .onChange(of: Array(apiServices)) { services in
                    viewModel.updateServices(services)
                }
        }
    }
    
    private var popoverContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)
            
            Divider()
            
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(viewModel.filteredSections) { section in
                        if section.id == "favorites" {
                            Section {
                                ForEach(section.items) { item in
                                    modelRow(item: item)
                                }
                            } header: {
                                sectionHeader(section.title, icon: "star.fill")
                            }
                        } else if section.id == "search" {
                            // Empty search results header if needed
                        } else {
                            Section {
                                ForEach(section.items) { item in
                                    modelRow(item: item)
                                }
                            } header: {
                                providerSectionHeader(title: section.title, provider: section.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)
        }
        .frame(minWidth: 320, maxWidth: 380)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func sectionHeader(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func providerSectionHeader(title: String, provider: String) -> some View {
        HStack(spacing: 6) {
            Image("logo_\(provider)")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 11, height: 11)
                .foregroundStyle(.tertiary)
            
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.tertiary)
            
            TextField("Search models...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
        )
    }
    
    private func modelRow(item: ModelSelectorViewModel.ModelItem) -> some View {
        let isSelected = (chat.apiService?.type == item.provider && chat.gptModel == item.modelId)
        let metadata = metadataCache.getMetadata(provider: item.provider, modelId: item.modelId)
        
        let isReasoning = metadata?.hasReasoning ?? false
        let isVision = metadata?.hasVision ?? false
        
        let formattedModel = ModelMetadata.formatModelComponents(modelId: item.modelId, provider: item.provider)
        
        return Button(action: {
            handleModelChange(providerType: item.provider, model: item.modelId)
            onDismiss?()
        }) {
            HStack(spacing: 10) {
                // Model name
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(formattedModel.displayName)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.accentColor : .primary)
                            .lineLimit(1)
                        
                        if let provider = formattedModel.provider {
                            Text("(\(provider))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Capabilities & pricing in subtitle
                    if isReasoning || isVision || (metadata?.hasPricing == true) {
                        HStack(spacing: 6) {
                            if isReasoning {
                                Label("Reasoning", systemImage: "brain")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            if isVision {
                                Label("Vision", systemImage: "eye")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            if let pricing = metadata?.pricing, let inputPrice = pricing.inputPer1M {
                                Text(pricing.outputPer1M != nil
                                    ? "$\(String(format: "%.2f", inputPrice))/$\(String(format: "%.2f", pricing.outputPer1M!))"
                                    : "$\(String(format: "%.2f", inputPrice))/M")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Favorite button
                    Button(action: {
                        favoriteManager.toggleFavorite(provider: item.provider, model: item.modelId)
                    }) {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 11))
                            .foregroundStyle(item.isFavorite ? Color.accentColor : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    
                    // Selection checkmark
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoveredItem == item.id ? Color.primary.opacity(0.04) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItem = hovering ? item.id : nil
        }
    }
    
    private func handleModelChange(providerType: String, model: String) {
        guard let service = apiServices.first(where: { $0.type == providerType }) else { return }
        
        chat.apiService = service
        chat.gptModel = model
        chat.updatedDate = Date()
        
        // Force immediate UI refresh for the sidebar and other observers
        chat.objectWillChange.send()
        
        try? viewContext.save()
        
        NotificationCenter.default.post(
            name: .recreateMessageManager,
            object: nil,
            userInfo: ["chatId": chat.id]
        )
    }
}

#Preview {
    StandaloneModelSelector(chat: PreviewStateManager.shared.sampleChat, isExpanded: true)
        .environmentObject(PreviewStateManager.shared.chatStore)
        .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
}

/// Canonical model selector entrypoint.
/// Thin wrapper over StandaloneModelSelector with toolbar-aligned trigger styling.
struct ModelSelectorDropdown: View {
    @ObservedObject var chat: ChatEntity
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject private var modelCache = ModelCacheManager.shared
    @StateObject private var selectedModelsManager = SelectedModelsManager.shared
    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    @State private var isExpanded = false
    @State private var isHovered = false
    
    private var currentProviderType: String {
        chat.apiService?.type ?? AppConstants.defaultApiType
    }
    
    private var currentProviderDisplayName: String {
        if let type = chat.apiService?.type,
           let config = AppConstants.defaultApiConfigurations[type] {
            return config.name
        }
        return chat.apiService?.name ?? "No AI Service"
    }
    
    private var currentModelLabel: String {
        guard let service = chat.apiService else {
            return "Select Model"
        }
        let modelId = chat.gptModel
        if modelId.isEmpty {
            return "Select Model"
        }

        // Prefer friendly label from cache if available
        let models = modelCache.getModels(for: service.type ?? currentProviderType)
        if let match = models.first(where: { $0.id == modelId }) {
            // AIModel currently exposes only `id`; use that directly as the label.
            return match.id
        }
        return modelId
    }
    
    private var hasMultipleVisibleModels: Bool {
        // Use the same visibility rules as StandaloneModelSelector / SelectedModelsManager.
        guard let providerType = chat.apiService?.type else { return false }
        let models = modelCache.getModelsSorted(for: providerType)
        return models.count > 1
    }
    
    var body: some View {
        Button(action: {
            isExpanded = true
            if isExpanded {
                triggerModelFetchIfNeeded()
            }
        }) {
            HStack(spacing: 8) {
                // Provider logo
                Image("logo_\(currentProviderType)")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(currentModelLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(currentProviderDisplayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if hasMultipleVisibleModels {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            StandaloneModelSelector(chat: chat, isExpanded: true, onDismiss: {
                isExpanded = false
            })
                .environment(\.managedObjectContext, viewContext)
        }
        .onAppear {
            triggerModelFetchIfNeeded()
        }
    }
    
    private func triggerModelFetchIfNeeded() {
        let services = Array(apiServices)
        guard !services.isEmpty else { return }
        
        // Delegate deduping/conditions to ModelCacheManager; this is a safe, local entry point.
        modelCache.fetchAllModels(from: services)
        
        // Ensure SelectedModelsManager has visibility config; cheap no-op if already loaded.
        SelectedModelsManager.shared.loadSelections(from: services)
    }
}

// Simple model row component
struct ModelRowView: View {
    let provider: String
    let model: AIModel
    let isSelected: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        HStack {
            Text(model.id)
                .font(.system(size: 11))
                .foregroundColor(isSelected ? .accentColor : .primary)
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { onHover($0) }
    }
}

// Preview
struct StandaloneModelSelector_Previews: PreviewProvider {
    static var previews: some View {
        StandaloneModelSelector(chat: PreviewStateManager.shared.sampleChat, isExpanded: true)
            .frame(width: 300)
            .padding()
            .environmentObject(PreviewStateManager.shared.chatStore)
    }
} 
