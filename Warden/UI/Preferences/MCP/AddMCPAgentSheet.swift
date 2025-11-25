import SwiftUI

struct AddMCPAgentSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: MCPManager
    var configToEdit: MCPServerConfig?
    
    @State private var name: String = ""
    @State private var transportType: MCPServerConfig.TransportType = .stdio
    @State private var command: String = ""
    @State private var arguments: String = "" // Space separated for simplicity, or multiline
    @State private var environment: String = "" // Key=Value per line
    @State private var urlString: String = ""
    
    @State private var testStatus: String? = nil
    @State private var isTesting: Bool = false
    
    var body: some View {
        Form {
            Section("General") {
                TextField("Name", text: $name)
                Picker("Transport", selection: $transportType) {
                    ForEach(MCPServerConfig.TransportType.allCases, id: \.self) { type in
                        Text(type.rawValue.uppercased()).tag(type)
                    }
                }
            }
            
            if transportType == .stdio {
                Section("Command Configuration") {
                    TextField("Command (e.g. npx)", text: $command)
                    TextField("Arguments (space separated)", text: $arguments)
                    TextEditor(text: $environment)
                        .frame(height: 100)
                        .overlay(alignment: .topLeading) {
                            if environment.isEmpty {
                                Text("Environment Variables (KEY=VALUE per line)")
                                    .foregroundColor(.gray)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            } else {
                Section("Network Configuration") {
                    TextField("URL (e.g. http://localhost:3000/sse)", text: $urlString)
                }
            }
            
            Section {
                if let status = testStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(status.contains("Success") ? .green : .red)
                }
                
                Button(action: testConnection) {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(name.isEmpty || (transportType == .stdio && command.isEmpty) || (transportType == .sse && urlString.isEmpty) || isTesting)
                
                Button(configToEdit != nil ? "Save Changes" : "Add Agent") {
                    saveAgent()
                }
                .disabled(name.isEmpty || (transportType == .stdio && command.isEmpty) || (transportType == .sse && urlString.isEmpty) || isTesting)
                
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }
        }
        .padding()
        .frame(width: 400, height: 500)
        .onAppear {
            if let config = configToEdit {
                name = config.name
                transportType = config.transportType
                
                if let cmd = config.command {
                    command = cmd
                }
                
                arguments = config.arguments.joined(separator: " ")
                
                environment = config.environment.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
                
                if let url = config.url {
                    urlString = url.absoluteString
                }
            }
        }
    }
    
    private func testConnection() {
        isTesting = true
        testStatus = nil
        
        let config = createConfigFromState()
        
        Task {
            do {
                let toolCount = try await manager.testConnection(config: config)
                await MainActor.run {
                    testStatus = "Success! Found \(toolCount) tools."
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testStatus = "Connection failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
    
    private func createConfigFromState() -> MCPServerConfig {
        var config = MCPServerConfig(
            name: name,
            transportType: transportType
        )
        
        if transportType == .stdio {
            config.command = command
            config.arguments = arguments.split(separator: " ").map(String.init)
            
            var envDict: [String: String] = [:]
            environment.enumerateLines { line, _ in
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    envDict[String(parts[0])] = String(parts[1])
                }
            }
            config.environment = envDict
            config.url = nil
        } else {
            config.url = URL(string: urlString)
            config.command = nil
            config.arguments = []
            config.environment = [:]
        }
        
        return config
    }
    
    private func saveAgent() {
        var config = createConfigFromState()
        
        // Preserve ID if editing
        if let existingConfig = configToEdit {
            config.id = existingConfig.id
        }
        
        if configToEdit != nil {
            manager.updateConfig(config)
        } else {
            manager.addConfig(config)
        }
        dismiss()
    }
}
