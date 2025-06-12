import SwiftUI
import CoreData

struct ModelSelectionView: View {
    let serviceType: String
    let availableModels: [AIModel]
    let onSelectionChanged: (Set<String>) -> Void
    
    @StateObject private var selectedModelsManager = SelectedModelsManager.shared
    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    
    @State private var searchText = ""
    @State private var showAllModels = false
    
    private var selectedModelIds: Set<String> {
        selectedModelsManager.getSelectedModelIds(for: serviceType)
    }
    
    private var hasCustomSelection: Bool {
        selectedModelsManager.hasCustomSelection(for: serviceType)
    }
    
    private var filteredModels: [AIModel] {
        let models = showAllModels ? availableModels : defaultAndFavoriteModels
        
        if searchText.isEmpty {
            return models.sorted { $0.id < $1.id }
        }
        
        return models.filter { model in
            model.id.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.id < $1.id }
    }
    
    private var defaultAndFavoriteModels: [AIModel] {
        let defaultConfig = AppConstants.defaultApiConfigurations[serviceType]
        let defaultModelIds = Set(defaultConfig?.models ?? [])
        let favoriteModelIds = Set(favoriteManager.getFavorites(for: serviceType))
        
        return availableModels.filter { model in
            defaultModelIds.contains(model.id) || favoriteModelIds.contains(model.id)
        }
    }
    
    private var selectedCount: Int {
        hasCustomSelection ? selectedModelIds.count : availableModels.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            
            if !availableModels.isEmpty {
                searchAndControls
                modelsList
            } else {
                emptyState
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Model Selection")
                    .font(.headline)
                
                Spacer()
                
                if hasCustomSelection {
                    Button("Reset to All") {
                        resetToAllModels()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            
            Text("Choose which models appear in the chat model selector. By default, all models are shown.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text("\(selectedCount) of \(availableModels.count) models selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if hasCustomSelection {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
    }
    
    private var searchAndControls: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            
            HStack {
                Toggle("Show all models", isOn: $showAllModels)
                    .font(.caption)
                
                Spacer()
                
                if !showAllModels {
                    Text("Default + Favorites")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
    }
    
    private var modelsList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(filteredModels, id: \.id) { model in
                    ModelSelectionRow(
                        model: model,
                        serviceType: serviceType,
                        isSelected: isModelSelected(model),
                        onToggle: { isSelected in
                            toggleModel(model, isSelected: isSelected)
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 200)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("No models available")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Configure the API service to load models")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
    
    private func isModelSelected(_ model: AIModel) -> Bool {
        if hasCustomSelection {
            return selectedModelIds.contains(model.id)
        }
        return true // All models are selected when no custom selection
    }
    
    private func toggleModel(_ model: AIModel, isSelected: Bool) {
        var newSelection = selectedModelIds
        
        // If no custom selection exists, start with all models
        if !hasCustomSelection {
            newSelection = Set(availableModels.map { $0.id })
        }
        
        if isSelected {
            newSelection.insert(model.id)
        } else {
            newSelection.remove(model.id)
        }
        
        selectedModelsManager.setSelectedModels(for: serviceType, modelIds: newSelection)
        onSelectionChanged(newSelection)
    }
    
    private func resetToAllModels() {
        selectedModelsManager.clearCustomSelection(for: serviceType)
        onSelectionChanged(Set())
    }
}

struct ModelSelectionRow: View {
    let model: AIModel
    let serviceType: String
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    
    private var isFavorite: Bool {
        favoriteManager.isFavorite(provider: serviceType, model: model.id)
    }
    
    private var isReasoningModel: Bool {
        AppConstants.openAiReasoningModels.contains(model.id) ||
        model.id.lowercased().contains("reasoning") ||
        model.id.lowercased().contains("thinking")
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                onToggle(!isSelected)
            }) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            
            HStack(spacing: 6) {
                Text(model.id)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption2)
                }
                
                if isReasoningModel {
                    Text("thinking")
                        .font(.caption2)
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle(!isSelected)
        }
        .background(
            isSelected ? Color.accentColor.opacity(0.1) : Color.clear
        )
        .cornerRadius(4)
    }
}

#Preview {
    ModelSelectionView(
        serviceType: "chatgpt",
        availableModels: [
            AIModel(id: "gpt-4o"),
            AIModel(id: "gpt-4o-mini"),
            AIModel(id: "o1-preview"),
            AIModel(id: "claude-3-5-sonnet-latest"),
        ],
        onSelectionChanged: { _ in }
    )
    .frame(width: 400, height: 500)
} 