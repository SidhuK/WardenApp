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
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider().opacity(0.5)
            
            if isCreating {
                creatingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                ModelSelectorList(
                    apiServices: Array(apiServices),
                    selectedProviderType: nil,
                    selectedModelId: nil,
                    dismissOnSelect: false,
                    onDismiss: nil,
                    onSelect: { provider, model in
                        createBranch(providerType: provider, model: model)
                    }
                )
            }
        }
        .frame(width: 420, height: 520)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Create Branch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(origin == .user ? "Select AI to generate response" : "Select AI to continue chat")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
    
    // MARK: - Creating State
    
    private var creatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(0.9)
            
            VStack(spacing: 4) {
                Text("Creating branch...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(origin == .user ? "Generating AI response" : "Preparing conversation")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            
            VStack(spacing: 4) {
                Text("Branch Failed")
                    .font(.system(size: 13, weight: .semibold))
                
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            
            Button(action: { errorMessage = nil }) {
                Text("Try Again")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Branch Creation
    
    @MainActor
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
