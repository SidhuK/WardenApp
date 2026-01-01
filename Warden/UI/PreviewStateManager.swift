
import SwiftUI
import CoreData
import Foundation

@MainActor
final class PreviewStateManager: ObservableObject {
    @Published var isPreviewVisible = false
    @Published var previewContent = ""
    @AppStorage("previewPaneWidth") var previewPaneWidth: Double = 400
    
    // Singleton for preview use
    static let shared = PreviewStateManager()
    
    // Preview data
    lazy var persistenceController: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        
        // Create sample project
        let sampleProject = ProjectEntity(context: context)
        sampleProject.id = UUID()
        sampleProject.name = "Sample Project"
        sampleProject.projectDescription = "A sample project for testing"
        sampleProject.colorCode = "#007AFF"
        sampleProject.customInstructions = "You are helping with a sample project. Be helpful and concise."
        sampleProject.createdAt = Date()
        sampleProject.updatedAt = Date()
        sampleProject.isArchived = false
        sampleProject.sortOrder = 0
        
        // Create sample chat
        let sampleChat = ChatEntity(context: context)
        sampleChat.id = UUID()
        sampleChat.name = "Sample Chat"
        sampleChat.createdDate = Date()
        sampleChat.updatedDate = Date()
        sampleChat.gptModel = AppConstants.chatGptDefaultModel
        sampleChat.project = sampleProject
        
        // Create sample persona
        let persona = PersonaEntity(context: context)
        persona.name = "Assistant"
        persona.color = "person.circle"
        sampleChat.persona = persona
        
        try? context.save()
        return controller
    }()
    
    lazy var chatStore: ChatStore = {
        ChatStore(persistenceController: persistenceController)
    }()
    
    var sampleProject: ProjectEntity? {
        let context = persistenceController.container.viewContext
        let request = ProjectEntity.fetchRequest()
        return try? context.fetch(request).first
    }
    
    var sampleChat: ChatEntity {
        let context = persistenceController.container.viewContext
        let request = ChatEntity.fetchRequest()
        if let existingChat = try? context.fetch(request).first {
            return existingChat as! ChatEntity
        }
        
        // Create a new sample chat if none exists
        let sampleChat = ChatEntity(context: context)
        sampleChat.id = UUID()
        sampleChat.name = "Sample Chat"
        sampleChat.createdDate = Date()
        sampleChat.updatedDate = Date()
        sampleChat.gptModel = AppConstants.chatGptDefaultModel
        sampleChat.project = sampleProject
        
        // Create sample persona
        let persona = PersonaEntity(context: context)
        persona.name = "Assistant"
        persona.color = "person.circle"
        sampleChat.persona = persona
        
        try? context.save()
        return sampleChat
    }
    
    func showPreview(content: String) {
        previewContent = content
        isPreviewVisible = true
    }
    
    func hidePreview() {
        isPreviewVisible = false
    }
}
