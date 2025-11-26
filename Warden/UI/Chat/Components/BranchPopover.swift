import SwiftUI
import CoreData

/// Inline popover for creating conversation branches with model selection
struct BranchPopover: View {
    let sourceMessage: MessageEntity
    let sourceChat: ChatEntity
    let origin: BranchOrigin
    let onBranchCreated: (ChatEntity) -> Void
    let onDismiss: () -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = ModelSelectorViewModel()
    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    @StateObject private var metadataCache = ModelMetadataCache.shared
    
    @State private var hoveredItem: String? = nil
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            if isCreating {
                creatingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                // Search bar
                searchBar
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                
                Divider()
                
                // Model list
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
                            } else if section.id != "search" {
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
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 340)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            viewModel.updateServices(Array(apiServices))
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Branch")
                    .font(.system(size: 13, weight: .semibold))
                
                Text(origin == .user ? "Select AI for new response" : "Select AI to continue")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary)
            
            TextField("Search models...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.textBackgroundColor))
        )
    }
    
    // MARK: - Section Headers
    
    private func sectionHeader(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func providerSectionHeader(title: String, provider: String) -> some View {
        HStack(spacing: 5) {
            Image("logo_\(provider)")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 10, height: 10)
                .foregroundStyle(.tertiary)
            
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Model Row
    
    private func modelRow(item: ModelSelectorViewModel.ModelItem) -> some View {
        let metadata = metadataCache.getMetadata(provider: item.provider, modelId: item.modelId)
        let isReasoning = metadata?.hasReasoning ?? false
        let isVision = metadata?.hasVision ?? false
        let formattedModel = ModelMetadata.formatModelComponents(modelId: item.modelId, provider: item.provider)
        
        return Button(action: {
            createBranch(providerType: item.provider, model: item.modelId)
        }) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(formattedModel.displayName)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if let provider = formattedModel.provider {
                            Text("(\(provider))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if isReasoning || isVision {
                        HStack(spacing: 5) {
                            if isReasoning {
                                Label("Reasoning", systemImage: "brain")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                            if isVision {
                                Label("Vision", systemImage: "eye")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Favorite button
                Button(action: {
                    favoriteManager.toggleFavorite(provider: item.provider, model: item.modelId)
                }) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundStyle(item.isFavorite ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hoveredItem == item.id ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItem = hovering ? item.id : nil
        }
    }
    
    // MARK: - Creating State
    
    private var creatingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text("Creating branch...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.orange)
            
            Text(error)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                errorMessage = nil
            }
            .font(.system(size: 11))
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    // MARK: - Branch Creation
    
    private func createBranch(providerType: String, model: String) {
        guard let service = apiServices.first(where: { $0.type == providerType }) else {
            errorMessage = "Service not found"
            return
        }
        
        isCreating = true
        
        Task {
            do {
                let manager = ChatBranchingManager(viewContext: viewContext)
                let newChat = try await manager.createBranch(
                    from: sourceChat,
                    at: sourceMessage,
                    origin: origin,
                    targetService: service,
                    targetModel: model,
                    autoGenerate: origin == .user
                )
                
                await MainActor.run {
                    isCreating = false
                    onBranchCreated(newChat)
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
