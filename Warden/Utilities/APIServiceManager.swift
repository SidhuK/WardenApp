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
    ///   - maxTokens: Maximum tokens in response (currently not used by all handlers)
    ///   - temperature: Temperature for AI generation
    /// - Returns: Generated summary text
    func generateSummary(prompt: String, maxTokens: Int = 800, temperature: Float = 0.3) async throws -> String {
        // Get the user's preferred API service from UserDefaults
        let currentAPIServiceName = UserDefaults.standard.string(forKey: "currentAPIService") ?? "ChatGPT"
        
        // Try to find a matching API service entity
        let apiService = findAPIServiceForSummarization(preferredType: currentAPIServiceName)
        
        guard let service = apiService else {
            throw APIError.noApiService("No suitable API service available for summarization")
        }
        
        // Create API configuration
        guard let config = createAPIConfiguration(for: service) else {
            throw APIError.noApiService("Failed to create API configuration for summarization")
        }
        
        // Create API service instance using factory
        let apiServiceInstance = APIServiceFactory.createAPIService(config: config)
        
        // Prepare messages for summarization request
        let requestMessages = prepareSummarizationMessages(prompt: prompt, model: service.model ?? "")
        
        #if DEBUG
        print("🤖 Generating summary using \(service.name ?? "Unknown") service")
        print("📝 Model: \(service.model ?? "Unknown")")
        #endif
        
        // Use async/await with continuation to bridge callback-based API
        return try await withCheckedThrowingContinuation { continuation in
            apiServiceInstance.sendMessage(requestMessages, temperature: temperature) { result in
                switch result {
                case .success(let response):
                    let cleanedResponse = self.cleanSummarizationResponse(response)
                    continuation.resume(returning: cleanedResponse)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Finds the best available API service for summarization
    private func findAPIServiceForSummarization(preferredType: String) -> APIServiceEntity? {
        let allServices = getAllAPIServices()
        
        // First, try to find the user's preferred service type
        if let preferredService = allServices.first(where: { 
            $0.type?.lowercased() == preferredType.lowercased() 
        }) {
            return preferredService
        }
        
        // Fallback to any available service (prioritize reliable ones for summarization)
        let priorityOrder = ["chatgpt", "claude", "gemini", "deepseek", "perplexity"]
        
        for serviceType in priorityOrder {
            if let service = allServices.first(where: { 
                $0.type?.lowercased() == serviceType 
            }) {
                return service
            }
        }
        
        // Last resort: return any available service
        return allServices.first
    }
    
    /// Creates API configuration for the given service
    private func createAPIConfiguration(for service: APIServiceEntity) -> APIServiceConfiguration? {
        guard let apiServiceUrl = service.url,
              let serviceType = service.type else {
            return nil
        }
        
        // Get API key from secure storage
        var apiKey = ""
        do {
            apiKey = try TokenManager.getToken(for: service.id?.uuidString ?? "") ?? ""
        } catch {
            print("Error extracting token for summarization: \(error)")
            return nil
        }
        
        // Ensure we have a valid API key
        guard !apiKey.isEmpty else {
            print("No API key available for service: \(service.name ?? "Unknown")")
            return nil
        }
        
        return APIServiceConfig(
            name: serviceType,
            apiUrl: apiServiceUrl,
            apiKey: apiKey,
            model: service.model ?? getDefaultModelForService(serviceType)
        )
    }
    
    /// Prepares messages specifically formatted for summarization requests
    private func prepareSummarizationMessages(prompt: String, model: String) -> [[String: String]] {
        var messages: [[String: String]] = []
        
        // For reasoning models (o1, o3), we need to handle system message differently
        if AppConstants.openAiReasoningModels.contains(model) {
            // Reasoning models don't support system role, so we embed instructions in user message
            let combinedPrompt = """
            You are an AI assistant specialized in creating concise and insightful project summaries. Your task is to analyze project data and generate comprehensive summaries that highlight key themes, progress, and insights.
            
            Please provide a clear, well-structured summary for the following project:
            
            \(prompt)
            
            Focus on:
            - Key themes and topics
            - Project progress and insights
            - Notable patterns or achievements
            - Areas of focus or expertise demonstrated
            
            Keep the summary informative but concise (under 500 words).
            """
            
            messages.append([
                "role": "user",
                "content": combinedPrompt
            ])
        } else {
            // Standard models support system role
            messages.append([
                "role": "system",
                "content": """
                You are an AI assistant specialized in creating concise and insightful project summaries. 
                Your task is to analyze project data and generate comprehensive summaries that highlight 
                key themes, progress, and insights. Focus on extracting meaningful patterns and providing 
                actionable insights. Keep summaries informative but concise (under 500 words).
                """
            ])
            
            messages.append([
                "role": "user",
                "content": prompt
            ])
        }
        
        return messages
    }
    
    /// Gets default model for a service type
    private func getDefaultModelForService(_ serviceType: String) -> String {
        switch serviceType.lowercased() {
        case "chatgpt":
            return AppConstants.chatGptDefaultModel
        case "claude":
            return "claude-3-5-sonnet-20241022"
        case "gemini":
            return "gemini-1.5-pro"
        case "deepseek":
            return "deepseek-chat"
        case "perplexity":
            return "llama-3.1-sonar-small-128k-online"
        default:
            return AppConstants.chatGptDefaultModel
        }
    }
    
    /// Cleans and formats the AI response for better presentation
    private func cleanSummarizationResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove any markdown formatting that might be problematic
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        
        // Ensure the response isn't too long
        if cleaned.count > 1000 {
            // Truncate at the last complete sentence within limit
            let truncated = String(cleaned.prefix(950))
            if let lastPeriod = truncated.lastIndex(of: ".") {
                cleaned = String(truncated[...lastPeriod])
            } else {
                cleaned = truncated + "..."
            }
        }
        
        return cleaned
    }
}
