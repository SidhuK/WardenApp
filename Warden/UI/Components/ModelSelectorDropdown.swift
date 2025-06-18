import SwiftUI
import CoreData

struct StandaloneModelSelector: View {
    @ObservedObject var chat: ChatEntity
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject private var modelCache = ModelCacheManager.shared
    @StateObject private var selectedModelsManager = SelectedModelsManager.shared
    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    @State private var isExpanded = false
    @State private var searchText = ""
    @State private var hoveredItem: String? = nil
    @State private var showOnlyFavorites = false
    
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
        HStack {
            Spacer()
            
            VStack(spacing: 0) {
                selectorButton
                
                if isExpanded {
                    dropdownContent
                        .transition(.opacity)
                        .zIndex(1000) // Ensure it appears above other content
                }
            }
            .frame(maxWidth: 400) // Approximately 45% of typical chat width
            .background(Color.clear)
            
            Spacer()
        }
        .onAppear {
            modelCache.fetchAllModels(from: Array(apiServices))
        }
        .onChange(of: apiServices.count) { _, _ in
            modelCache.fetchAllModels(from: Array(apiServices))
        }
    }
    
    private var selectorButton: some View {
        Button(action: {
            // Instantaneous animation
            withAnimation(.easeInOut(duration: 0.05)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 8) {
                // Provider logo
                Image("logo_\(currentProvider)")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Text(currentProviderName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(currentModel)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color.primary.opacity(0.04), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
                    )
                    .shadow(
                        color: Color.black.opacity(0.05),
                        radius: 2,
                        x: 0,
                        y: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var dropdownContent: some View {
        VStack(spacing: 0) {
            // Header with search and favorites toggle
            VStack(spacing: 8) {
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
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.85))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.top, 4)
        .fixedSize(horizontal: false, vertical: true) // Allow content to determine height
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
                        .fill(Color(NSColor.textBackgroundColor).opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                )
    }
    
    private var favoritesToggle: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.05)) {
                showOnlyFavorites.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: showOnlyFavorites ? "heart.fill" : "heart")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(showOnlyFavorites ? .red : .secondary)
                
                Text(showOnlyFavorites ? "Show All Models" : "Show Favorites Only")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(showOnlyFavorites ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(showOnlyFavorites ? Color.red.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(showOnlyFavorites ? Color.red.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
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
            .background(Color.primary.opacity(0.04))
            
            // Models
            ForEach(models, id: \.self) { model in
                modelRow(provider: provider, model: model)
            }
        }
    }
    
    private func modelRow(provider: String, model: String) -> some View {
        Button(action: {
            handleModelChange(providerType: provider, model: model)
            withAnimation(.easeInOut(duration: 0.05)) {
                isExpanded = false
            }
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
                    .foregroundColor(.primary)
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
                Rectangle()
                    .fill(hoveredItem == "\(provider)_\(model)" ? 
                          Color.accentColor.opacity(0.08) : Color.clear)
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
    StandaloneModelSelector(chat: PreviewStateManager.shared.sampleChat)
        .environmentObject(PreviewStateManager.shared.chatStore)
        .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
}

// Keep the original ModelSelectorDropdown as a simple placeholder
struct ModelSelectorDropdown: View {
    @Binding var selectedProvider: String
    @Binding var selectedModel: String
    @Binding var isVisible: Bool
    let chat: ChatEntity?
    let onModelChange: (String, String) -> Void
    
    var body: some View {
        VStack {
            Text("Model Selector")
                .font(.headline)
            Text("Coming Soon")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
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
        StandaloneModelSelector(chat: PreviewStateManager.shared.sampleChat)
            .frame(width: 300)
            .padding()
            .environmentObject(PreviewStateManager.shared.chatStore)
    }
} 
