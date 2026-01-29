import SwiftUI
import CoreData

// MARK: - Model Selector Dropdown (Toolbar)

struct ModelSelectorDropdown: View {
    @ObservedObject var chat: ChatEntity
    
    @ObservedObject private var modelCache = ModelCacheManager.shared
    @ObservedObject private var selectedModelsManager = SelectedModelsManager.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
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
        let modelId = chat.gptModel
        if modelId.isEmpty { return "Select Model" }
        return ModelMetadata.formatModelDisplayName(modelId: modelId, provider: currentProviderType)
    }
    
    private var hasMultipleVisibleModels: Bool {
        guard let providerType = chat.apiService?.type else { return false }
        return modelCache.getModelsSorted(for: providerType).count > 1
    }
    
    @MainActor
    private func selectModel(provider: String, modelId: String) {
        if let service = apiServices.first(where: { $0.type == provider }) {
            chat.apiService = service
        }
        chat.gptModel = modelId
        chat.updatedDate = Date()
        chat.objectWillChange.send()
        
        NotificationCenter.default.post(
            name: .recreateMessageManager,
            object: nil,
            userInfo: ["chatId": chat.id]
        )
    }
    
    var body: some View {
        ModelSelectorPopoverButton(
            apiServices: Array(apiServices),
            selectedProviderType: chat.apiService?.type,
            selectedModelId: chat.gptModel.isEmpty ? nil : chat.gptModel,
            popoverWidth: 460,
            popoverHeight: 600,
            arrowEdge: .bottom,
            onSelect: { provider, modelId in
                selectModel(provider: provider, modelId: modelId)
            }
        ) {
            HStack(spacing: 8) {
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
        }
        .fixedSize()
        .onHover { isHovered = $0 }
        .task {
            let services = Array(apiServices)
            guard !services.isEmpty else { return }
            modelCache.fetchAllModels(from: services)
            selectedModelsManager.loadSelections(from: services)
        }
    }
}

// MARK: - Preview

#Preview {
    ModelSelectorDropdown(
        chat: PreviewStateManager.shared.sampleChat
    )
    .environmentObject(PreviewStateManager.shared.chatStore)
    .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
}
