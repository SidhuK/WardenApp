import Foundation
import MCP

@MainActor
class MCPManager: ObservableObject {
    static let shared = MCPManager()
    
    @Published var configs: [MCPServerConfig] = []
    @Published var clients: [UUID: MCPClient] = [:]
    
    // Cache for tool to agent mapping
    private var toolOwner: [String: UUID] = [:]
    
    private let configsKey = "MCPServerConfigs"
    
    init() {
        loadConfigs()
    }
    
    // ... (load/save/add/update/delete/connect/disconnect methods remain same) ...
    
    func loadConfigs() {
        if let data = UserDefaults.standard.data(forKey: configsKey),
           let decoded = try? JSONDecoder().decode([MCPServerConfig].self, from: data) {
            self.configs = decoded
        }
    }
    
    func saveConfigs() {
        if let encoded = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(encoded, forKey: configsKey)
        }
    }
    
    func addConfig(_ config: MCPServerConfig) {
        configs.append(config)
        saveConfigs()
    }
    
    func updateConfig(_ config: MCPServerConfig) {
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
            saveConfigs()
            // Reconnect if needed
            Task {
                await disconnect(id: config.id)
                if config.enabled {
                    try? await connect(config: config)
                }
            }
        }
    }
    
    func deleteConfig(id: UUID) {
        configs.removeAll { $0.id == id }
        saveConfigs()
        Task {
            await disconnect(id: id)
        }
    }
    
    func connect(config: MCPServerConfig) async throws {
        guard config.enabled else { return }
        
        let transport: Transport
        switch config.transportType {
        case .stdio:
            guard let command = config.command else { return }
            transport = StdioTransport(
                command: command,
                arguments: config.arguments,
                environment: config.environment
            )
        case .sse:
            guard let url = config.url else { return }
            transport = SSETransport(url: url)
        }
        
        let client = MCPClient(transport: transport)
        try await client.start()
        clients[config.id] = client
    }
    
    func disconnect(id: UUID) async {
        if let client = clients[id] {
            try? await client.stop()
            clients.removeValue(forKey: id)
            // Remove tools for this client from cache
            toolOwner = toolOwner.filter { $0.value != id }
        }
    }
    
    func restartAll() async {
        for config in configs where config.enabled {
            try? await connect(config: config)
        }
    }
    
    // MARK: - Tool Handling
    
    func getTools(for agentIDs: Set<UUID>) async -> [MCP.Tool] {
        var allTools: [MCP.Tool] = []
        
        for id in agentIDs {
            guard let client = clients[id] else {
                // Try to connect if not connected?
                // For now assume connected.
                continue
            }
            
            do {
                let result = try await client.listTools()
                for tool in result.tools {
                    allTools.append(tool)
                    toolOwner[tool.name] = id
                }
            } catch {
                print("Error fetching tools for agent \(id): \(error)")
            }
        }
        
        return allTools
    }
    
    func callTool(name: String, arguments: [String: Any]) async throws -> Any {
        guard let agentID = toolOwner[name], let client = clients[agentID] else {
            throw NSError(domain: "MCPManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Tool not found or agent not connected"])
        }
        
        let result = try await client.callTool(name: name, arguments: arguments)
        return result
    }
}
