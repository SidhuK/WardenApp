import CoreData
import Foundation

/// Manages simultaneous communication with multiple AI services.
@MainActor
final class MultiAgentMessageManager: ObservableObject {
    private var groupTask: Task<Void, Never>?

    @Published var activeAgents: [AgentResponse] = []
    @Published var isProcessing = false

    init(viewContext: NSManagedObjectContext) {
        _ = viewContext
    }

    func stopStreaming() {
        groupTask?.cancel()
        groupTask = nil

        isProcessing = false

        for index in activeAgents.indices where !activeAgents[index].isComplete {
            activeAgents[index].isComplete = true
            activeAgents[index].error = APIError.unknown("Request cancelled by user")
        }
    }

    /// Represents a response from a single agent/service.
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
            "\(serviceName) (\(model))"
        }
    }

    /// Sends a message to multiple AI services simultaneously.
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

        groupTask?.cancel()

        // Limit to maximum 3 services for optimal UX.
        let limitedServices = Array(selectedServices.prefix(3))

        isProcessing = true
        activeAgents = limitedServices.map { service in
            AgentResponse(
                serviceName: service.name ?? "Unknown",
                serviceType: service.type ?? "unknown",
                model: service.model ?? "unknown"
            )
        }

        let requestMessages = chat.constructRequestMessages(forUserMessage: message, contextSize: contextSize)
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()
        let settings = GenerationSettings(temperature: temperature, reasoningEffort: chat.reasoningEffort)

        groupTask = Task { [weak self] in
            guard let self else { return }

            await withTaskGroup(of: Void.self) { group in
                for (agentIndex, service) in limitedServices.enumerated() {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await Self.sendRequest(
                            service: service,
                            requestMessages: requestMessages,
                            settings: settings,
                            updateAgent: { update in
                                await MainActor.run { [weak self] in
                                    guard let self, agentIndex < self.activeAgents.count else { return }
                                    update(&self.activeAgents[agentIndex])
                                }
                            }
                        )
                    }
                }
            }

            guard !Task.isCancelled else { return }
            isProcessing = false
            groupTask = nil
            completion(.success(activeAgents))
        }
    }
}

private extension MultiAgentMessageManager {
    static func sendRequest(
        service: APIServiceEntity,
        requestMessages: [[String: String]],
        settings: GenerationSettings,
        updateAgent: @Sendable @escaping (@Sendable (inout AgentResponse) -> Void) async -> Void
    ) async {
        guard let config = APIServiceManager.createAPIConfiguration(for: service) else {
            await updateAgent { agent in
                agent.error = APIError.noApiService("Invalid configuration")
                agent.isComplete = true
                agent.timestamp = Date()
            }
            return
        }

        let apiService = APIServiceFactory.createAPIService(config: config)

        await updateAgent { agent in
            agent.response = ""
            agent.isComplete = false
            agent.error = nil
            agent.timestamp = Date()
        }

        do {
            if service.useStreamResponse {
                let updateInterval = AppConstants.streamedResponseUpdateUIInterval
                var pendingParts: [String] = []
                var pendingCharacterCount = 0
                var lastFlushTime = Date.distantPast

                func drainPendingParts() -> String {
                    var result = String()
                    result.reserveCapacity(pendingCharacterCount)
                    for part in pendingParts {
                        result.append(contentsOf: part)
                    }
                    pendingParts.removeAll(keepingCapacity: true)
                    pendingCharacterCount = 0
                    return result
                }

                func flushPendingParts(force: Bool) async {
                    guard !pendingParts.isEmpty else { return }
                    let now = Date()
                    guard force || now.timeIntervalSince(lastFlushTime) >= updateInterval else { return }
                    let chunk = drainPendingParts()
                    lastFlushTime = now

                    await updateAgent { agent in
                        agent.response.append(contentsOf: chunk)
                        agent.timestamp = Date()
                    }
                }

                _ = try await ChatService.shared.sendStream(
                    apiService: apiService,
                    messages: requestMessages,
                    settings: settings
                ) { chunk in
                    pendingParts.append(chunk)
                    pendingCharacterCount += chunk.count
                    await flushPendingParts(force: false)
                }

                await flushPendingParts(force: true)
            } else {
                let responseText = try await sendMessage(
                    apiService: apiService,
                    requestMessages: requestMessages,
                    settings: settings
                )

                await updateAgent { agent in
                    agent.response = responseText ?? "No response"
                    agent.timestamp = Date()
                }
            }

            if !Task.isCancelled {
                await updateAgent { agent in
                    agent.isComplete = true
                    agent.timestamp = Date()
                }
            }
        } catch is CancellationError {
            await updateAgent { agent in
                agent.error = APIError.unknown("Request cancelled")
                agent.isComplete = true
                agent.timestamp = Date()
            }
        } catch {
            await updateAgent { agent in
                agent.error = error as? APIError ?? APIError.unknown(error.localizedDescription)
                agent.isComplete = true
                agent.timestamp = Date()
            }
        }
    }

    static func sendMessage(
        apiService: APIService,
        requestMessages: [[String: String]],
        settings: GenerationSettings
    ) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            ChatService.shared.sendMessage(
                apiService: apiService,
                messages: requestMessages,
                settings: settings
            ) { result in
                switch result {
                case .success(let (responseText, _)):
                    continuation.resume(returning: responseText)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
