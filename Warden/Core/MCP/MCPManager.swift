import Foundation
import SwiftUI
import MCP

@MainActor
class MCPManager: ObservableObject {
    static let shared = MCPManager()
    
    @Published var configs: [MCPServerConfig] = []
    @Published var clients: [UUID: Client] = [:]
    
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
        
        let client = Client(name: "Warden", version: "1.0")
        
        switch config.transportType {
        case .stdio:
            // Note: StdioTransport in the SDK doesn't take arguments
            // For now, we'll use the basic transport
            let transport = StdioTransport()
            _ = try await client.connect(transport: transport)
            
        case .sse:
            guard let url = config.url else { return }
            let transport = HTTPClientTransport(endpoint: url, streaming: true)
            _ = try await client.connect(transport: transport)
        }
        
        clients[config.id] = client
    }
    
    func disconnect(id: UUID) async {
        if let client = clients[id] {
            // Client doesn't have close(), just remove from dict
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
    
    func getTools(for agentIDs: Set<UUID>) async -> [Tool] {
        var allTools: [Tool] = []
        
        for id in agentIDs {
            guard let client = clients[id] else {
                // Try to connect if not connected?
                // For now assume connected.
                continue
            }
            
            do {
                let (tools, _) = try await client.listTools()
                for tool in tools {
                    allTools.append(tool)
                    toolOwner[tool.name] = id
                }
            } catch {
                print("Error fetching tools for agent \(id): \(error)")
            }
        }
        
        return allTools
    }
    
    func callTool(name: String, arguments: [String: Any]) async throws -> [[String: Any]] {
        guard let agentID = toolOwner[name], let client = clients[agentID] else {
            throw NSError(domain: "MCPManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Tool not found or agent not connected"])
        }
        
        // Convert [String: Any] to [String: Value]
        var valueArgs: [String: Value] = [:]
        for (key, value) in arguments {
            if let strVal = value as? String {
                valueArgs[key] = try .init(strVal)
            } else if let intVal = value as? Int {
                valueArgs[key] = try .init(Double(intVal))
            } else if let doubleVal = value as? Double {
                valueArgs[key] = try .init(doubleVal)
            } else if let boolVal = value as? Bool {
                valueArgs[key] = try .init(boolVal)
            }
            // Add more type conversions as needed
        }
        
        let (content, _) = try await client.callTool(name: name, arguments: valueArgs)
        
        // Convert content to JSON-compatible format
        var result: [[String: Any]] = []
        for item in content {
            switch item {
            case .text(let text):
                result.append(["type": "text", "text": text])
            case .image(let img):
                result.append(["type": "image", "mimeType": img.mimeType])
            case .resource(let res):
                var dict: [String: Any] = ["type": "resource",  "uri": res.uri, "mimeType": res.mimeType]
                if let text = res.text {
                    dict["text"] = text
                }
                result.append(dict)
            @unknown default:
                // Handle any future cases
                result.append(["type": "unknown"])
            }
        }
        
        return result
    }
}
