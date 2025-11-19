import SwiftUI
import CoreData
import Combine

// ViewModel to handle heavy lifting of sorting and filtering
class ModelSelectorViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var filteredSections: [ModelSection] = []
    
    // Data sources
    private let modelCache = ModelCacheManager.shared
    private let selectedModelsManager = SelectedModelsManager.shared
    private let favoriteManager = FavoriteModelsManager.shared
    private let recentModelsManager = RecentModelsManager.shared
    
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
            .sink { [weak self] _ in self?.refreshData() }
            .store(in: &cancellables)
            
        recentModelsManager.objectWillChange
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
            
            let recents = getRecents(from: availableModels)
            if !recents.isEmpty {
                sections.append(ModelSection(id: "recents", title: "Recently Used", items: recents))
            }
        } else {
            sections.append(ModelSection(id: "search", title: "Search Results", items: []))
        }
        
        // 2. All Models (Filtered)
        let filtered = getFilteredModels(from: availableModels)
        
        // If searching, we just show one flat list in the "Search Results" section usually, 
        // or we can keep provider sections. The original code kept provider sections.
        // Let's stick to the original design: Provider sections.
        
        // However, for the "All Models" part, we need to exclude favs/recents if not searching
        let favIds = Set(sections.first(where: { $0.id == "favorites" })?.items.map { $0.id } ?? [])
        let recentIds = Set(sections.first(where: { $0.id == "recents" })?.items.map { $0.id } ?? [])
        let excludeIds = favIds.union(recentIds)
        
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
        
        // If searching, we might want to flatten or keep structure. Original kept structure.
        // But wait, if we have "Search Results" header in original, it was just a header.
        // The original code:
        // if !searchText.isEmpty { sectionHeader("Search Results") }
        // ForEach(remainingFilteredModels) { providerSection... }
        
        // So we just append the provider sections to the main list
        sections.append(contentsOf: providerSections)
        
        DispatchQueue.main.async {
            self.filteredSections = sections
        }
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
                // as favorites/recents are handled separately.
                // Original code had a complex score, but mostly for fav/recent.
                // Since we separate those, alphabetical is fine and FASTER.
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
    
    private func getRecents(from available: [(provider: String, models: [String])]) -> [ModelItem] {
        let allRecent = recentModelsManager.getRecentModels()
        return allRecent.prefix(5).compactMap { recent in
            // Verify it's still available
            let isAvailable = available.contains { $0.provider == recent.provider && $0.models.contains(recent.modelId) }
            guard isAvailable else { return nil }
            
            return ModelItem(
                id: "\(recent.provider)_\(recent.modelId)",
                provider: recent.provider,
                modelId: recent.modelId,
                isFavorite: favoriteManager.isFavorite(provider: recent.provider, model: recent.modelId)
            )
        }
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
    @StateObject private var recentModelsManager = RecentModelsManager.shared
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
                .padding(.horizontal, 8)
                .padding(.top, 8)
            
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(viewModel.filteredSections) { section in
                        if section.id == "favorites" || section.id == "recents" {
                            sectionHeader(section.title)
                            ForEach(section.items) { item in
                                modelRow(item: item)
                            }
                            Divider().padding(.vertical, 4)
                        } else if section.id == "search" {
                            sectionHeader(section.title)
                        } else {
                            // Provider section
                            providerSectionHeader(title: section.title, provider: section.id)
                            ForEach(section.items) { item in
                                modelRow(item: item)
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 280)
        }
        .frame(minWidth: 340, maxWidth: 400)
        .padding(.vertical, 8)
        .background(AppConstants.backgroundElevated)
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func providerSectionHeader(title: String, provider: String) -> some View {
        HStack(spacing: 8) {
            Image("logo_\(provider)")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 12, height: 12)
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            TextField("Search models...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(AppConstants.backgroundInput)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppConstants.borderSubtle, lineWidth: 0.5)
                )
        )
    }
    
    private func modelRow(item: ModelSelectorViewModel.ModelItem) -> some View {
        // Use local vars to avoid capturing self if possible, but we need managers
        let isSelected = (chat.apiService?.type == item.provider && chat.gptModel == item.modelId)
        let metadata = metadataCache.getMetadata(provider: item.provider, modelId: item.modelId)
        
        let isReasoning = metadata?.hasReasoning ?? false
        let isVision = metadata?.hasVision ?? false
        
        return Button(action: {
            handleModelChange(providerType: item.provider, model: item.modelId)
            onDismiss?()
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Selection Indicator
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                    
                    Text(ModelMetadata.formatModelDisplayName(modelId: item.modelId, provider: item.provider))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(isSelected ? .accentColor : AppConstants.textPrimary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        // Favorite
                        Button(action: {
                            favoriteManager.toggleFavorite(provider: item.provider, model: item.modelId)
                        }) {
                            Image(systemName: item.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 9))
                                .foregroundColor(item.isFavorite ? .yellow : .secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        
                        if isReasoning {
                            Image(systemName: "brain")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        }
                        if isVision {
                            Image(systemName: "eye")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // Pricing
                if let metadata = metadata, metadata.hasPricing, let pricing = metadata.pricing, let inputPrice = pricing.inputPer1M {
                    HStack(spacing: 8) {
                        Text(metadata.costIndicator)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                        
                        let priceText = pricing.outputPer1M != nil 
                            ? "$\(String(format: "%.2f", inputPrice)) → $\(String(format: "%.2f", pricing.outputPer1M!))/1M"
                            : "$\(String(format: "%.2f", inputPrice))/1M"
                            
                        Text(priceText)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 16)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoveredItem == item.id ? AppConstants.backgroundSubtle : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItem = hovering ? item.id : nil
        }
    }
    
    private func handleModelChange(providerType: String, model: String) {
        guard let service = apiServices.first(where: { $0.type == providerType }) else { return }
        
        recentModelsManager.recordUsage(provider: providerType, modelId: model)
        
        chat.apiService = service
        chat.gptModel = model
        
        try? viewContext.save()
        
        NotificationCenter.default.post(
            name: NSNotification.Name("RecreateMessageManager"),
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
            // Single-click opens the full selector immediately.
            isExpanded = true

            // Lazy-load models when user opens the selector.
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
                    .foregroundColor(AppConstants.textSecondary)
                    .opacity(chat.apiService == nil ? 0.6 : 1.0)

                VStack(alignment: .leading, spacing: 1) {
                    // Current model
                    Text(currentModelLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppConstants.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Provider / hint
                    Text(currentProviderDisplayName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(AppConstants.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                // Chevron only if there are choices; keeps UI lightweight.
                if hasMultipleVisibleModels {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppConstants.textSecondary)
                        .padding(.leading, 4)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 360)
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            // Directly render the full selector content, without an extra nested trigger.
            StandaloneModelSelector(chat: chat, isExpanded: true, onDismiss: {
                withAnimation(.easeInOut(duration: 0.05)) {
                    isExpanded = false
                }
            })
                .environment(\.managedObjectContext, viewContext)
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, minHeight: 260, maxHeight: 320)
        }
        .onAppear {
            // Prime cache once using current active services; avoid repeated global fetches.
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
