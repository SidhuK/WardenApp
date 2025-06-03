
import CoreData
import Foundation

/// Manages simultaneous communication with multiple AI services
class MultiAgentMessageManager: ObservableObject {
    private var viewContext: NSManagedObjectContext
    private var lastUpdateTime = Date()
    private let updateInterval = AppConstants.streamedResponseUpdateUIInterval
    
    @Published var activeAgents: [AgentResponse] = []
    @Published var isProcessing = false
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
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
        Task {
            do {
                let stream = try await apiService.sendMessageStream(requestMessages, temperature: temperature)
                var accumulatedResponse = ""
                
                for try await chunk in stream {
                    accumulatedResponse += chunk
                    
                    await MainActor.run {
                        if agentIndex < self.activeAgents.count {
                            self.activeAgents[agentIndex].response = accumulatedResponse
                            self.activeAgents[agentIndex].timestamp = Date()
                        }
                    }
                }
                
                await MainActor.run {
                    if agentIndex < self.activeAgents.count {
                        self.activeAgents[agentIndex].response = accumulatedResponse
                        self.activeAgents[agentIndex].isComplete = true
                        self.activeAgents[agentIndex].timestamp = Date()
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
        
        // Use persona's system message if available, otherwise fall back to chat's system message
        let systemMessage = chat.persona?.systemMessage ?? chat.systemMessage
        
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
} 
