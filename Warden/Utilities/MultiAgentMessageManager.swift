import CoreData
import Foundation

/// Manages simultaneous communication with multiple AI services
class MultiAgentMessageManager: ObservableObject {
    private var viewContext: NSManagedObjectContext
    private var lastUpdateTime = Date()
    private let updateInterval = AppConstants.streamedResponseUpdateUIInterval
    private var activeTasks: [Task<Void, Never>] = []
    
    @Published var activeAgents: [AgentResponse] = []
    @Published var isProcessing = false
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }
    
    func stopStreaming() {
        // Cancel all active tasks
        activeTasks.forEach { $0.cancel() }
        activeTasks.removeAll()
        
        // Update state
        isProcessing = false
        
        // Mark incomplete agents as cancelled
        for index in activeAgents.indices {
            if !activeAgents[index].isComplete {
                activeAgents[index].isComplete = true
                activeAgents[index].error = APIError.unknown("Request cancelled by user")
            }
        }
    }
    
    /// Represents a response from a single agent/service
    struct AgentResponse: Identifiable {
        let id = UUID()
        let serviceName: String
        let serviceType: String
        let model: String
        var response: String = ""
        var isComplete: Bool = false
        var error: APIError?
        var timestamp: Date = Date()
        
        var displayName: String {
            return "\(serviceName) (\(model))"
        }
    }
    
    /// Sends a message to multiple AI services simultaneously
    func sendMessageToMultipleServices(
        _ message: String,
        chat: ChatEntity,
        selectedServices: [APIServiceEntity],
        contextSize: Int,
        completion: @escaping (Result<[AgentResponse], Error>) -> Void
    ) {
        guard !selectedServices.isEmpty else {
            completion(.failure(APIError.noApiService("No services selected")))
            return
        }
        
        // Limit to maximum 3 services for optimal UX
        let limitedServices = Array(selectedServices.prefix(3))
        
        isProcessing = true
        activeAgents = []
        activeTasks.removeAll() // Clear any previous tasks
        
        let requestMessages = constructRequestMessages(chat: chat, forUserMessage: message, contextSize: contextSize)
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()
        
        let dispatchGroup = DispatchGroup()
        
        // Create initial agent responses
        for service in limitedServices {
            let agentResponse = AgentResponse(
                serviceName: service.name ?? "Unknown",
                serviceType: service.type ?? "unknown",
                model: service.model ?? "unknown"
            )
            activeAgents.append(agentResponse)
        }
        
        // Send requests to all services concurrently
        for (index, service) in limitedServices.enumerated() {
            dispatchGroup.enter()
            
            guard let config = loadAPIConfig(for: service) else {
                activeAgents[index].error = APIError.noApiService("Invalid configuration")
                activeAgents[index].isComplete = true
                dispatchGroup.leave()
                continue
            }
            
            let apiService = APIServiceFactory.createAPIService(config: config)
            
            // Use streaming if supported
            if service.useStreamResponse {
                sendStreamRequest(
                    apiService: apiService,
                    requestMessages: requestMessages,
                    temperature: temperature,
                    agentIndex: index,
                    dispatchGroup: dispatchGroup
                )
            } else {
                sendRegularRequest(
                    apiService: apiService,
                    requestMessages: requestMessages,
                    temperature: temperature,
                    agentIndex: index,
                    dispatchGroup: dispatchGroup
                )
            }
        }
        
        // Wait for all requests to complete
        dispatchGroup.notify(queue: .main) {
            self.isProcessing = false
            self.activeTasks.removeAll() // Clear completed tasks
            completion(.success(self.activeAgents))
        }
    }
    
    private func sendStreamRequest(
        apiService: APIService,
        requestMessages: [[String: String]],
        temperature: Float,
        agentIndex: Int,
        dispatchGroup: DispatchGroup
    ) {
        let task = Task {
            do {
                let stream = try await apiService.sendMessageStream(requestMessages, temperature: temperature)
                var accumulatedResponse = ""
                
                for try await chunk in stream {
                    // Check for cancellation
                    try Task.checkCancellation()
                    
                    accumulatedResponse += chunk
                    
                    await MainActor.run {
                        if agentIndex < self.activeAgents.count {
                            self.activeAgents[agentIndex].response = accumulatedResponse
                            self.activeAgents[agentIndex].timestamp = Date()
                        }
                    }
                }
                
                // Only complete if not cancelled
                if !Task.isCancelled {
                    await MainActor.run {
                        if agentIndex < self.activeAgents.count {
                            self.activeAgents[agentIndex].response = accumulatedResponse
                            self.activeAgents[agentIndex].isComplete = true
                            self.activeAgents[agentIndex].timestamp = Date()
                        }
                    }
                }
                
                dispatchGroup.leave()
            } catch is CancellationError {
                await MainActor.run {
                    if agentIndex < self.activeAgents.count {
                        self.activeAgents[agentIndex].error = APIError.unknown("Request cancelled")
                        self.activeAgents[agentIndex].isComplete = true
                    }
                }
                dispatchGroup.leave()
            } catch {
                await MainActor.run {
                    if agentIndex < self.activeAgents.count {
                        self.activeAgents[agentIndex].error = error as? APIError ?? APIError.unknown(error.localizedDescription)
                        self.activeAgents[agentIndex].isComplete = true
                    }
                }
                dispatchGroup.leave()
            }
        }
        
        // Track the task for potential cancellation
        activeTasks.append(task)
    }
    
    private func sendRegularRequest(
        apiService: APIService,
        requestMessages: [[String: String]],
        temperature: Float,
        agentIndex: Int,
        dispatchGroup: DispatchGroup
    ) {
        apiService.sendMessage(requestMessages, temperature: temperature) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, agentIndex < self.activeAgents.count else {
                    dispatchGroup.leave()
                    return
                }
                
                switch result {
                case .success(let response):
                    self.activeAgents[agentIndex].response = response
                    self.activeAgents[agentIndex].isComplete = true
                    self.activeAgents[agentIndex].timestamp = Date()
                    
                case .failure(let error):
                    self.activeAgents[agentIndex].error = error
                    self.activeAgents[agentIndex].isComplete = true
                }
                
                dispatchGroup.leave()
            }
        }
    }
    
    private func loadAPIConfig(for service: APIServiceEntity) -> APIServiceConfiguration? {
        guard let apiServiceUrl = service.url else {
            return nil
        }
        
        var apiKey = ""
        do {
            apiKey = try TokenManager.getToken(for: service.id?.uuidString ?? "") ?? ""
        } catch {
            print("Error extracting token: \(error) for \(service.id?.uuidString ?? "")")
        }
        
        return APIServiceConfig(
            name: service.type ?? "chatgpt",
            apiUrl: apiServiceUrl,
            apiKey: apiKey,
            model: service.model ?? AppConstants.chatGptDefaultModel
        )
    }
    
    private func constructRequestMessages(chat: ChatEntity, forUserMessage userMessage: String?, contextSize: Int) -> [[String: String]] {
        var messages: [[String: String]] = []
        
        // Build comprehensive system message with project context - same logic as MessageManager
        let systemMessage = buildSystemMessageWithProjectContext(for: chat)
        
        if !AppConstants.openAiReasoningModels.contains(chat.gptModel) {
            messages.append([
                "role": "system",
                "content": systemMessage,
            ])
        } else {
            // Models like o1-mini and o1-preview don't support "system" role
            messages.append([
                "role": "user",
                "content": "Take this message as the system message: \(systemMessage)",
            ])
        }
        
        let sortedMessages = chat.messagesArray
            .sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
            .suffix(contextSize)
        
        // Add conversation history
        for message in sortedMessages {
            messages.append([
                "role": message.own ? "user" : "assistant",
                "content": message.body,
            ])
        }
        
        // Add the new user message
        if let userMessage = userMessage {
            messages.append([
                "role": "user",
                "content": userMessage,
            ])
        }
        
        return messages
    }
    
    /// Builds a comprehensive system message that includes project context, project instructions, and persona instructions
    /// Handles instruction precedence: project instructions + persona instructions + chat-specific instructions
    /// This mirrors the same method in MessageManager for consistency
    private func buildSystemMessageWithProjectContext(for chat: ChatEntity) -> String {
        var systemMessageComponents: [String] = []
        
        // 1. Start with base persona system message or chat system message
        let baseSystemMessage = chat.persona?.systemMessage ?? chat.systemMessage
        if !baseSystemMessage.isEmpty {
            systemMessageComponents.append(baseSystemMessage)
        }
        
        // 2. Add project context if available
        if let project = chat.project {
            // Provide basic project info
            let projectInfo = """
            
            PROJECT CONTEXT:
            You are working within the "\(project.name ?? "Untitled Project")" project.
            """
            if let description = project.projectDescription, !description.isEmpty {
                systemMessageComponents.append(projectInfo + " Project description: \(description)")
            } else {
                systemMessageComponents.append(projectInfo)
            }
            
            // 3. Add project-specific custom instructions
            if let customInstructions = project.customInstructions, !customInstructions.isEmpty {
                let projectInstructions = """
                
                PROJECT-SPECIFIC INSTRUCTIONS:
                \(customInstructions)
                """
                systemMessageComponents.append(projectInstructions)
            }
        }
        
        // 4. Combine all components into final system message
        return systemMessageComponents.joined(separator: "\n")
    }
} 
