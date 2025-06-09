

import Foundation
import CoreData

class APIServiceManager {
    private let viewContext: NSManagedObjectContext
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }
    
    func createAPIService(name: String, type: String, url: URL, model: String, contextSize: Int16, useStreamResponse: Bool, generateChatNames: Bool) -> APIServiceEntity {
        let apiService = APIServiceEntity(context: viewContext)
        apiService.id = UUID()
        apiService.name = name
        apiService.type = type
        apiService.url = url
        apiService.model = model
        apiService.contextSize = contextSize
        apiService.useStreamResponse = useStreamResponse
        apiService.generateChatNames = generateChatNames
        apiService.tokenIdentifier = UUID().uuidString
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving API service: \(error)")
        }
        
        return apiService
    }
    
    func updateAPIService(_ apiService: APIServiceEntity, name: String, type: String, url: URL, model: String, contextSize: Int16, useStreamResponse: Bool, generateChatNames: Bool) {
        apiService.name = name
        apiService.type = type
        apiService.url = url
        apiService.model = model
        apiService.contextSize = contextSize
        apiService.useStreamResponse = useStreamResponse
        apiService.generateChatNames = generateChatNames
        
        do {
            try viewContext.save()
        } catch {
            print("Error updaring API service: \(error)")
        }
    }
    
    func deleteAPIService(_ apiService: APIServiceEntity) {
        viewContext.delete(apiService)
        
        do {
            try viewContext.save()
        } catch {
            print("Error deleting API service: \(error)")
        }
    }
    
    func getAllAPIServices() -> [APIServiceEntity] {
        let fetchRequest: NSFetchRequest<APIServiceEntity> = APIServiceEntity.fetchRequest()
        
        do {
            return try viewContext.fetch(fetchRequest)
        } catch {
            print("Error fetching API services: \(error)")
            return []
        }
    }
    
    func getAPIService(withID id: UUID) -> APIServiceEntity? {
        let fetchRequest: NSFetchRequest<APIServiceEntity> = APIServiceEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            return results.first
        } catch {
            print("Error fetching API service: \(error)")
            return nil
        }
    }
    
    // MARK: - AI Summarization Support
    
    /// Generates a summary using the user's preferred AI service
    /// - Parameters:
    ///   - prompt: The prompt for summarization
    ///   - maxTokens: Maximum tokens in response
    ///   - temperature: Temperature for AI generation
    /// - Returns: Generated summary text
    func generateSummary(prompt: String, maxTokens: Int = 800, temperature: Float = 0.3) async throws -> String {
        // For now, this is a placeholder implementation
        // In a real implementation, this would use the actual API handlers
        // and the user's preferred service from UserDefaults
        
        // Get the user's preferred API service
        _ = UserDefaults.standard.string(forKey: "currentAPIService") ?? "ChatGPT"
        
        // Create a simple mock response for now
        // TODO: Implement actual API call using APIServiceFactory and user's preferred service
        try await Task.sleep(nanoseconds: 1_000_000_000) // Simulate API delay
        
        // This would be replaced with actual API integration
        return """
        This project appears to be focused on \(extractProjectType(from: prompt)). 
        Based on the chat content analysis, the main themes include software development, 
        problem-solving, and technical discussions. The project shows active engagement 
        with multiple conversations covering various aspects of the topic.
        
        Key insights suggest this is an ongoing effort with regular activity and 
        meaningful progress being made through collaborative discussions.
        """
    }
    
    /// Extracts likely project type from the prompt for mock response
    private func extractProjectType(from prompt: String) -> String {
        let lowercased = prompt.lowercased()
        
        if lowercased.contains("code") || lowercased.contains("programming") || lowercased.contains("development") {
            return "software development"
        } else if lowercased.contains("research") || lowercased.contains("analysis") {
            return "research and analysis"
        } else if lowercased.contains("writing") || lowercased.contains("content") {
            return "content creation"
        } else if lowercased.contains("learning") || lowercased.contains("study") {
            return "learning and education"
        } else {
            return "collaborative work"
        }
    }
}
