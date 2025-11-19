import SwiftUI
import CoreData

struct StandaloneModelSelector: View {
    @ObservedObject var chat: ChatEntity
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject private var modelCache = ModelCacheManager.shared
    @StateObject private var selectedModelsManager = SelectedModelsManager.shared
    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    @StateObject private var recentModelsManager = RecentModelsManager.shared
    @StateObject private var metadataCache = ModelMetadataCache.shared
    @State private var searchText = ""
    @State private var hoveredItem: String? = nil
    @State private var isHovered = false
    
    // Allow parent to control expanded state when used in popover
    var isExpanded: Bool = true
    var onDismiss: (() -> Void)? = nil
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    private var currentProvider: String {
        chat.apiService?.type ?? "chatgpt"
    }
    
    private var currentProviderName: String {
        chat.apiService?.name ?? "No AI Service"
    }
    
    private var currentModel: String {
        chat.gptModel.isEmpty ? "No Model" : chat.gptModel
    }
    
    private var availableModels: [(provider: String, models: [String])] {
        var result: [(provider: String, models: [String])] = []
        
        for service in apiServices {
            guard let serviceType = service.type else { continue }
            
            // Get cached models for this service
            let serviceModels = modelCache.getModels(for: serviceType)
            
            // Filter models based on user's visibility preferences
            let visibleModels = serviceModels.filter { model in
                // Check if there are custom selections - if not, show all models
                if selectedModelsManager.hasCustomSelection(for: serviceType) {
                    return selectedModelsManager.getSelectedModelIds(for: serviceType).contains(model.id)
                } else {
                    return true  // Show all models if no custom selection
                }
            }
            
            if !visibleModels.isEmpty {
                result.append((provider: serviceType, models: visibleModels.map { $0.id }))
            }
        }
        
        return result
    }
    
    private var filteredModels: [(provider: String, models: [String])] {
        var modelsToFilter = availableModels
        
        // Apply search filter
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            modelsToFilter = modelsToFilter.compactMap { provider, models in
                let filteredModels = models.filter { model in
                    model.lowercased().contains(searchLower) ||
                    provider.lowercased().contains(searchLower)
                }
                return filteredModels.isEmpty ? nil : (provider: provider, models: filteredModels)
            }
        }
        
        // Smart sorting: favorites → recently used → alphabetical
        return modelsToFilter.map { provider, models in
            // Pre-calculate all scores in one pass
            let modelsWithScores = models.map { model in
                (model: model, score: calculateModelScore(model, provider: provider))
            }
            
            let sortedModels = modelsWithScores.sorted { first, second in
                if first.score != second.score {
                    return first.score > second.score
                }
                return first.model < second.model
            }
            .map { $0.model }
            
            return (provider: provider, models: sortedModels)
        }
    }
    
    // Get all favorite models across all providers
    private var favoriteModelsFlat: [(provider: String, model: String)] {
        availableModels.flatMap { provider, models in
            models.filter { model in
                favoriteManager.isFavorite(provider: provider, model: model)
            }
            .map { model in
                (provider: provider, model: model)
            }
        }
    }
    
    // Get all recently used models across all providers (limited to 5)
    private var recentlyUsedModelsFlat: [(provider: String, model: String)] {
        let allRecentModels = recentModelsManager.getRecentModels()
        // Filter to only available models and limit to 5
        return allRecentModels.prefix(5).filter { recent in
            availableModels.contains { provider, models in
                provider == recent.provider && models.contains(recent.modelId)
            }
        }
        .map { recent in
            (provider: recent.provider, model: recent.modelId)
        }
    }
    
    // Get remaining models excluding favorites and recently used
    private var remainingFilteredModels: [(provider: String, models: [String])] {
        let favoriteIds = Set(favoriteModelsFlat.map { "\($0.provider)_\($0.model)" })
        let recentIds = Set(recentlyUsedModelsFlat.map { "\($0.provider)_\($0.model)" })
        
        return filteredModels.compactMap { provider, models in
            let remaining = models.filter { model in
                !favoriteIds.contains("\(provider)_\(model)") &&
                !recentIds.contains("\(provider)_\(model)")
            }
            return remaining.isEmpty ? nil : (provider: provider, models: remaining)
        }
    }
    
    private func calculateModelScore(_ model: String, provider: String) -> Int {
        var score = 0
        
        // Favorite bonus (highest priority)
        if favoriteManager.isFavorite(provider: provider, model: model) {
            score += 1000
        } else {
            // Recently used bonus (recency-based decay) - only check if not favorite
            if let lastUsed = recentModelsManager.getLastUsedDate(provider: provider, modelId: model) {
                let daysSinceUse = Calendar.current.dateComponents([.day], from: lastUsed, to: Date()).day ?? 999
                score += max(0, 100 - daysSinceUse)
            }
        }
        
        return score
    }
    
    var body: some View {
        if isExpanded {
            popoverContent
                .environment(\.managedObjectContext, viewContext)
        }
    }
    
    private var popoverContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(.horizontal, 8)
                .padding(.top, 8)
            
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    // Favorites Section (only show if not searching)
                    if searchText.isEmpty && !favoriteModelsFlat.isEmpty {
                        sectionHeader("Favorites")
                        
                        ForEach(Array(favoriteModelsFlat.enumerated()), id: \.offset) { idx, fav in
                            modelRow(provider: fav.provider, model: fav.model)
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                    }
                    
                    // Recently Used Section (only show if not searching)
                    if searchText.isEmpty && !recentlyUsedModelsFlat.isEmpty {
                        sectionHeader("Recently Used")
                        
                        ForEach(Array(recentlyUsedModelsFlat.enumerated()), id: \.offset) { idx, recent in
                            modelRow(provider: recent.provider, model: recent.model)
                        }
                        
                        if !remainingFilteredModels.isEmpty {
                            Divider()
                                .padding(.vertical, 4)
                        }
                    }
                    
                    // All Models Section
                    if !searchText.isEmpty {
                        sectionHeader("Search Results")
                    }
                    
                    ForEach(remainingFilteredModels, id: \.provider) { providerData in
                        providerSection(provider: providerData.provider, models: providerData.models)
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 280)
        }
        .frame(minWidth: 340, maxWidth: 400)
        .padding(.vertical, 8)
        .background(
            AppConstants.backgroundElevated
        )
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.clear)
    }
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            TextField("Search models...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
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
    

    private func providerSection(provider: String, models: [String]) -> some View {
        VStack(spacing: 0) {
            // Provider header
            HStack(spacing: 8) {
                Image("logo_\(provider)")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 12, height: 12)
                    .foregroundColor(.secondary)
                
                Text(getProviderDisplayName(provider))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.clear)
            
            // Models
            ForEach(models, id: \.self) { model in
                modelRow(provider: provider, model: model)
            }
        }
    }
    
    private func modelRow(provider: String, model: String) -> some View {
        // Pre-calculate values to avoid repeated lookups
        let isSelected = isCurrentlySelected(provider: provider, model: model)
        let isFavorite = favoriteManager.isFavorite(provider: provider, model: model)
        let metadata = metadataCache.getMetadata(provider: provider, modelId: model)
        
        // Use metadata for capability detection, fall back to false if no metadata
        let isReasoning = metadata?.hasReasoning ?? false
        let isVision = metadata?.hasVision ?? false
        
        return Button(action: {
            handleModelChange(providerType: provider, model: model)
            onDismiss?()
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Current selection indicator
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                        )
                    
                    Text(ModelMetadata.formatModelDisplayName(modelId: model, provider: provider))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(isSelected ? .accentColor : AppConstants.textPrimary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        // Favorite star
                        Button(action: {
                            favoriteManager.toggleFavorite(provider: provider, model: model)
                        }) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 9))
                                .foregroundColor(isFavorite ? .yellow : .secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Toggle favorite")
                        
                        // Model type indicators
                        if isReasoning {
                            Image(systemName: "brain")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                                .help("Reasoning model")
                        }
                        
                        if isVision {
                            Image(systemName: "eye")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                                .help("Vision model")
                        }
                    }
                }
                
                // Pricing info if available
                if let metadata = metadata,
                   metadata.hasPricing,
                   let pricing = metadata.pricing,
                   let inputPrice = pricing.inputPer1M {
                    HStack(spacing: 8) {
                        Text(metadata.costIndicator)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                        
                        if let outputPrice = pricing.outputPer1M {
                            Text("$\(String(format: "%.2f", inputPrice)) → $\(String(format: "%.2f", outputPrice))/1M")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundColor(.secondary)
                        } else {
                            Text("$\(String(format: "%.2f", inputPrice))/1M")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 16)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoveredItem == "\(provider)_\(model)" ? AppConstants.backgroundSubtle : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItem = hovering ? "\(provider)_\(model)" : nil
        }
        // Removed hover popover for performance - all info is already shown inline
    }
    
    private func isCurrentlySelected(provider: String, model: String) -> Bool {
        return chat.apiService?.type == provider && chat.gptModel == model
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
    
    private func handleModelChange(providerType: String, model: String) {
        // Find the API service for this provider type
        guard let service = apiServices.first(where: { $0.type == providerType }) else {
            print("⚠️ No API service found for provider type: \(providerType)")
            return
        }
        
        // Validate that the service has required configuration
        guard let serviceUrl = service.url, !serviceUrl.absoluteString.isEmpty else {
            print("⚠️ API service \(service.name ?? "Unknown") has invalid URL")
            return
        }
        
        // Record usage for recently used models tracking
        recentModelsManager.recordUsage(provider: providerType, modelId: model)
        
        // Update chat configuration
        chat.apiService = service
        chat.gptModel = model
        
        print("🔄 Model changed to \(providerType)/\(model) for chat \(chat.id)")
        
        do {
            try viewContext.save()
            
            // Send notification that model changed
            NotificationCenter.default.post(
                name: NSNotification.Name("RecreateMessageManager"),
                object: nil,
                userInfo: ["chatId": chat.id]
            )
            
            print("✅ Model change saved and notification sent")
        } catch {
            print("❌ Failed to save model change: \(error)")
        }
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
