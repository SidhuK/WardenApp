
import SwiftUI
import CoreData

struct ModelSelectorDropdown: View {
    @Binding var selectedProvider: String?
    @Binding var selectedModel: String?
    @Binding var isVisible: Bool
    
    let chat: ChatEntity?
    let onModelChange: (String, String) -> Void
    
    @StateObject private var modelCache = ModelCacheManager.shared
    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    @StateObject private var selectedModelsManager = SelectedModelsManager.shared
    @State private var searchText = ""
    @State private var hoveredItem: String? = nil
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    private var filteredModels: [(provider: String, model: AIModel)] {
        let allModels = modelCache.allModels
        
        if searchText.isEmpty {
            return allModels
        }
        
        return allModels.filter { item in
            let providerName = AppConstants.defaultApiConfigurations[item.provider]?.name ?? item.provider
            let modelName = item.model.id
            
            return providerName.localizedCaseInsensitiveContains(searchText) ||
                   modelName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // Group models by provider for better organization
    private var groupedModels: [(provider: String, providerName: String, models: [AIModel])] {
        let models = filteredModels.filter { item in
            !favoriteManager.isFavorite(provider: item.provider, model: item.model.id)
        }
        
        // Group by provider
        let grouped = Dictionary(grouping: models) { $0.provider }
        
        // Convert to sorted array with provider names
        return grouped.compactMap { (provider, items) in
            guard !items.isEmpty else { return nil }
            let providerName = AppConstants.defaultApiConfigurations[provider]?.name ?? provider
            let sortedModels = items.map { $0.model }.sorted { $0.id < $1.id }
            
            return (provider: provider, providerName: providerName, models: sortedModels)
        }.sorted { $0.providerName < $1.providerName }
    }
    
    // Get favorite models for the top section
    private var favoriteModels: [(provider: String, model: AIModel)] {
        return filteredModels.filter { item in
            favoriteManager.isFavorite(provider: item.provider, model: item.model.id)
        }.sorted { first, second in
            // Sort favorites by provider name, then model name
            let firstProviderName = AppConstants.defaultApiConfigurations[first.provider]?.name ?? first.provider
            let secondProviderName = AppConstants.defaultApiConfigurations[second.provider]?.name ?? second.provider
            
            if firstProviderName != secondProviderName {
                return firstProviderName < secondProviderName
            }
            return first.model.id < second.model.id
        }
    }
    
    private var currentSelection: String {
        guard let provider = selectedProvider, let model = selectedModel else {
            return "Select Model"
        }
        
        let providerName = AppConstants.defaultApiConfigurations[provider]?.name ?? provider
        return "\(providerName) • \(model)"
    }
    
    private var hasCustomModelSelection: Bool {
        // Check if any configured service has custom model selection
        return Array(apiServices).contains { service in
            guard let serviceType = service.type else { return false }
            return selectedModelsManager.hasCustomSelection(for: serviceType)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Trigger button
            Button(action: {
                withAnimation(.easeOut(duration: 0.15)) {
                    isVisible.toggle()
                }
                
                if isVisible {
                    // Fetch models when opening if not already cached
                    modelCache.fetchAllModels(from: Array(apiServices))
                }
            }) {
                HStack(spacing: 6) {
                    if let provider = selectedProvider {
                        Image("logo_\(provider)")
                            .resizable()
                            .renderingMode(.template)
                            .interpolation(.high)
                            .frame(width: 12, height: 12)
                            .foregroundColor(.accentColor)
                    } else {
                        Image(systemName: "cpu")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(currentSelection)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Image(systemName: isVisible ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Select AI Model")
            
            // Dropdown content
            if isVisible {
                dropdownContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private var dropdownContent: some View {
        VStack(spacing: 0) {
            // Search bar and custom selection indicator
            if !modelCache.allModels.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        TextField("Search models...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 11))
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    
                    // Custom selection indicator
                    if hasCustomModelSelection {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            
                            Text("Custom model selection active")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                
                // Divider
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 0.5)
            }
            
            // Models list with optimized scrolling
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    if favoriteModels.isEmpty && groupedModels.isEmpty {
                        emptyStateView
                    } else {
                        // Favorites section
                        if !favoriteModels.isEmpty {
                            favoritesSection
                            
                            // Divider between favorites and regular models
                            if !groupedModels.isEmpty {
                                sectionDivider
                            }
                        }
                        
                        // Provider-grouped models section
                        ForEach(Array(groupedModels.enumerated()), id: \.element.provider) { index, providerGroup in
                            providerSection(providerGroup, isLast: index == groupedModels.count - 1)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .scrollContentBackground(.hidden)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
    
    private var favoritesSection: some View {
        VStack(spacing: 0) {
            // Favorites header
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
                
                Text("Favorites")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(favoriteModels.count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.1))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // Favorite models (no dividers between different APIs)
            ForEach(favoriteModels, id: \.model.id) { item in
                ModelRowView(
                    provider: item.provider,
                    model: item.model,
                    isSelected: selectedProvider == item.provider && selectedModel == item.model.id,
                    isHovered: hoveredItem == "\(item.provider)_\(item.model.id)",
                    onTap: {
                        handleModelSelection(provider: item.provider, model: item.model.id)
                    },
                    onHover: { hovering in
                        hoveredItem = hovering ? "\(item.provider)_\(item.model.id)" : nil
                    }
                )
            }
        }
    }
    
    private func providerSection(_ providerGroup: (provider: String, providerName: String, models: [AIModel]), isLast: Bool) -> some View {
        VStack(spacing: 0) {
            providerHeader(providerGroup.provider, providerGroup.providerName, modelCount: providerGroup.models.count)
            
            ForEach(providerGroup.models, id: \.id) { model in
                ModelRowView(
                    provider: providerGroup.provider,
                    model: model,
                    isSelected: selectedProvider == providerGroup.provider && selectedModel == model.id,
                    isHovered: hoveredItem == "\(providerGroup.provider)_\(model.id)",
                    onTap: {
                        handleModelSelection(provider: providerGroup.provider, model: model.id)
                    },
                    onHover: { hovering in
                        hoveredItem = hovering ? "\(providerGroup.provider)_\(model.id)" : nil
                    }
                )
            }
            
            if !isLast {
                providerDivider()
            }
        }
    }
    
    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.2))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
    }
    
    private func providerHeader(_ provider: String, _ providerName: String, modelCount: Int) -> some View {
        HStack(spacing: 8) {
            Image("logo_\(provider)")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 12, height: 12)
                .foregroundColor(.accentColor)
            
            Text(providerName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Text("\(modelCount)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.1))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private func providerDivider() -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: searchText.isEmpty ? "cpu" : "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(searchText.isEmpty ? "No models available" : "No models found")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            if searchText.isEmpty {
                Text("Configure API services in Preferences")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding()
    }
    
    private func handleModelSelection(provider: String, model: String) {
        onModelChange(provider, model)
        withAnimation(.easeOut(duration: 0.1)) {
            isVisible = false
        }
        searchText = ""
    }
}

// MARK: - Optimized Model Row Component

struct ModelRowView: View {
    let provider: String
    let model: AIModel
    let isSelected: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    
    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    
    private var providerName: String {
        AppConstants.defaultApiConfigurations[provider]?.name ?? provider
    }
    
    private var isReasoningModel: Bool {
        AppConstants.openAiReasoningModels.contains(model.id)
    }
    
    private var isThinkingModel: Bool {
        model.id.lowercased().contains("thinking") || isReasoningModel
    }
    
    private var isFavorite: Bool {
        favoriteManager.isFavorite(provider: provider, model: model.id)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Provider logo (smaller when grouped)
            Image("logo_\(provider)")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 12, height: 12)
                .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.6))
            
            // Model name and details
            HStack(spacing: 6) {
                Text(model.id)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if isThinkingModel {
                    Text("thinking")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.purple.opacity(0.8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.purple.opacity(0.1))
                        )
                }
                
                Spacer()
            }
            
            // Selected checkbox
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
            
            // Favorite star button
            Button(action: {
                favoriteManager.toggleFavorite(provider: provider, model: model.id)
            }) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isFavorite ? .accentColor : .secondary.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(
            Rectangle()
                .fill(
                    isSelected 
                        ? Color.accentColor.opacity(0.1)
                        : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                )
        )
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            onHover(hovering)
        }
        .help("Select \(model.id) from \(providerName)")
    }
}

// MARK: - Preview

struct ModelSelectorDropdown_Previews: PreviewProvider {
    static var previews: some View {
        ModelSelectorDropdown(
            selectedProvider: .constant("chatgpt"),
            selectedModel: .constant("gpt-4o"),
            isVisible: .constant(true),
            chat: nil,
            onModelChange: { _, _ in }
        )
        .frame(width: 300)
        .padding()
    }
} 
