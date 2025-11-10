import SwiftUI
import CoreData

struct StandaloneModelSelector: View {
    @ObservedObject var chat: ChatEntity
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject private var modelCache = ModelCacheManager.shared
    @StateObject private var selectedModelsManager = SelectedModelsManager.shared
    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    @State private var searchText = ""
    @State private var hoveredItem: String? = nil
    @State private var showOnlyFavorites = false
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
            modelsToFilter = modelsToFilter.compactMap { provider, models in
                let filteredModels = models.filter { model in
                    model.lowercased().contains(searchText.lowercased()) ||
                    provider.lowercased().contains(searchText.lowercased())
                }
                return filteredModels.isEmpty ? nil : (provider: provider, models: filteredModels)
            }
        }
        
        // Apply favorites filter
        if showOnlyFavorites {
            modelsToFilter = modelsToFilter.compactMap { provider, models in
                let favoriteModels = models.filter { model in
                    favoriteManager.isFavorite(provider: provider, model: model)
                }
                return favoriteModels.isEmpty ? nil : (provider: provider, models: favoriteModels)
            }
        }
        
        // Sort models within each provider: favorites first, then alphabetically
        return modelsToFilter.map { provider, models in
            let sortedModels = models.sorted { model1, model2 in
                let isFav1 = favoriteManager.isFavorite(provider: provider, model: model1)
                let isFav2 = favoriteManager.isFavorite(provider: provider, model: model2)
                
                if isFav1 != isFav2 {
                    return isFav1 // Favorites first
                }
                return model1 < model2 // Then alphabetically
            }
            return (provider: provider, models: sortedModels)
        }
    }
    
    var body: some View {
        if isExpanded {
            popoverContent
                .environment(\.managedObjectContext, viewContext)
        }
    }
    
    private var popoverContent: some View {
        VStack(spacing: 0) {
            // Subtle top padding to separate from toolbar, no heavy border container.
            HStack(spacing: 8) {
                searchBar
                favoritesToggle
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(filteredModels, id: \.provider) { providerData in
                        providerSection(provider: providerData.provider, models: providerData.models)
                    }
                }
                .padding(.bottom, 4) // Add some bottom padding for smoother scrolling
            }
            .frame(maxHeight: 280) // Reduced height for better proportion
        }
        .frame(minWidth: 340, maxWidth: 400)
        .padding(.vertical, 8)
        .background(
            AppConstants.backgroundElevated
        )
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
    
    private var favoritesToggle: some View {
        HStack(spacing: 0) {
            // All button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.1)) {
                    showOnlyFavorites = false
                }
            }) {
                Text("All")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(!showOnlyFavorites ? .primary : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(!showOnlyFavorites ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Favorites button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.1)) {
                    showOnlyFavorites = true
                }
            }) {
                Text("Favorites")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(showOnlyFavorites ? .primary : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(showOnlyFavorites ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppConstants.backgroundChrome)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
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
        Button(action: {
            handleModelChange(providerType: provider, model: model)
            onDismiss?()
        }) {
            HStack(spacing: 8) {
                // Current selection indicator
                Circle()
                    .fill(isCurrentlySelected(provider: provider, model: model) ? 
                          Color.accentColor : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                    )
                
                Text(model)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(isCurrentlySelected(provider: provider, model: model) ? .accentColor : AppConstants.textPrimary)
                    .lineLimit(1)
                
                Spacer()
                
                HStack(spacing: 6) {
                    // Favorite star
                    Button(action: {
                        favoriteManager.toggleFavorite(provider: provider, model: model)
                    }) {
                        Image(systemName: favoriteManager.isFavorite(provider: provider, model: model) ? "star.fill" : "star")
                            .font(.system(size: 9))
                            .foregroundColor(favoriteManager.isFavorite(provider: provider, model: model) ? .yellow : .secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle favorite")
                    
                    // Model type indicators
                    if isReasoningModel(model) {
                        Image(systemName: "brain")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                            .help("Reasoning model")
                    }
                    
                    if isVisionModel(provider: provider, model: model) {
                        Image(systemName: "eye")
                            .font(.system(size: 9))
                            .foregroundColor(.blue)
                            .help("Vision model")
                    }
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
    }
    
    private func isCurrentlySelected(provider: String, model: String) -> Bool {
        return chat.apiService?.type == provider && chat.gptModel == model
    }
    
    private func isReasoningModel(_ model: String) -> Bool {
        // For now, only use OpenAI reasoning models since other constants don't exist yet
        return AppConstants.openAiReasoningModels.contains(model) ||
               model.contains("reasoning") ||
               model.contains("deepseek-reasoner") ||
               model.contains("sonar-reasoning")
    }
    
    private func isVisionModel(provider: String, model: String) -> Bool {
        // This would need to be implemented based on your vision model detection logic
        return model.contains("vision") || model.contains("4o") || model.contains("claude-3")
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
            // Keep the trigger visually minimal; remove any extra-looking outer chrome.
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppConstants.backgroundChrome.opacity(isHovered ? 0.9 : 0.6))
                    .stroke(AppConstants.borderSubtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: 360)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
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
