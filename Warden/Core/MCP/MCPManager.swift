import Foundation
import SwiftUI
import MCP
import Logging

@MainActor
class MCPManager: ObservableObject {
    static let shared = MCPManager()
    
    @Published var configs: [MCPServerConfig] = []
    @Published var clients: [UUID: Client] = [:]
    @Published var serverStatuses: [UUID: ServerStatus] = [:]
    
    enum ServerStatus: Equatable {
        case connected(toolsCount: Int)
        case disconnected
        case error(String)
        case connecting
    }
    
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
        
        await MainActor.run {
            serverStatuses[config.id] = .connecting
        }
        
        let client = Client(name: "Warden", version: "1.0")
        
        do {
            switch config.transportType {
            case .stdio:
                guard let command = config.command else {
                    throw NSError(domain: "MCPManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing command for Stdio transport"])
                }
                
                let transport = ProcessStdioTransport(command: command, arguments: config.arguments, environment: config.environment)
                _ = try await client.connect(transport: transport)
                
            case .sse:
                guard let url = config.url else {
                    throw NSError(domain: "MCPManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
                }
                let transport = HTTPClientTransport(endpoint: url, streaming: true)
                _ = try await client.connect(transport: transport)
            }
            
            clients[config.id] = client
            
            // Fetch tools to verify connection and get count
            let (tools, _) = try await client.listTools()
            
            // Update tool owner cache
            for tool in tools {
                toolOwner[tool.name] = config.id
            }
            
            await MainActor.run {
                serverStatuses[config.id] = .connected(toolsCount: tools.count)
            }
        } catch {
            await MainActor.run {
                serverStatuses[config.id] = .error(error.localizedDescription)
            }
            throw error
        }
    }
    
    func disconnect(id: UUID) async {
        if let client = clients[id] {
            // Client doesn't have close(), just remove from dict
            clients.removeValue(forKey: id)
            // Remove tools for this client from cache
            toolOwner = toolOwner.filter { $0.value != id }
            
            await MainActor.run {
                serverStatuses[id] = .disconnected
            }
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
    
    func testConnection(config: MCPServerConfig) async throws -> Int {
        let client = Client(name: "Warden-Test", version: "1.0")
        
        switch config.transportType {
        case .stdio:
            guard let command = config.command else {
                throw NSError(domain: "MCPManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing command for Stdio transport"])
            }
            let transport = ProcessStdioTransport(command: command, arguments: config.arguments, environment: config.environment)
            _ = try await client.connect(transport: transport)
            
        case .sse:
            guard let url = config.url else {
                throw NSError(domain: "MCPManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            let transport = HTTPClientTransport(endpoint: url, streaming: true)
            _ = try await client.connect(transport: transport)
        }
        
        let (tools, _) = try await client.listTools()
        return tools.count
    }
}

// Custom Transport implementation for Process-based Stdio
actor ProcessStdioTransport: Transport {
    public nonisolated let logger: Logger
    
    private let command: String
    private let arguments: [String]
    private let environment: [String: String]
    
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var isConnected = false
    
    private var receiveStream: AsyncThrowingStream<Data, Error>?
    private var receiveContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    
    init(command: String, arguments: [String], environment: [String: String], logger: Logger? = nil) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.logger = logger ?? Logger(label: "mcp.transport.process")
    }
    
    public func connect() async throws {
        guard !isConnected else { return }
        
        let process = Process()
        
        // Use /usr/bin/env to resolve commands in PATH (like npx, node, python)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env
        
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        self.receiveStream = AsyncThrowingStream { continuation = $0 }
        self.receiveContinuation = continuation
        
        try process.run()
        isConnected = true
        
        readLoop(handle: outputPipe.fileHandleForReading, continuation: continuation)
    }
    
    private nonisolated func readLoop(handle: FileHandle, continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        Task.detached {
            var buffer = Data()
            
            while !Task.isCancelled {
                let data = handle.availableData
                
                if data.isEmpty {
                    break
                }
                
                buffer.append(data)
                
                while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let messageData = buffer[..<newlineIndex]
                    buffer = buffer[(newlineIndex + 1)...]
                    if !messageData.isEmpty {
                        continuation.yield(Data(messageData))
                    }
                }
            }
            
            continuation.finish()
        }
    }
    
    public func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        
        receiveContinuation?.finish()
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
    }
    
    public func send(_ data: Data) async throws {
        guard let inputPipe = inputPipe else {
            throw NSError(domain: "ProcessStdioTransport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        
        var messageData = data
        messageData.append(UInt8(ascii: "\n"))
        try inputPipe.fileHandleForWriting.write(contentsOf: messageData)
    }
    
    public func receive() -> AsyncThrowingStream<Data, Error> {
        return receiveStream ?? AsyncThrowingStream { $0.finish() }
    }
}
