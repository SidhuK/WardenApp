import SwiftUI

struct AddMCPAgentSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: MCPManager
    
    @State private var name: String = ""
    @State private var transportType: MCPServerConfig.TransportType = .stdio
    @State private var command: String = ""
    @State private var arguments: String = "" // Space separated for simplicity, or multiline
    @State private var environment: String = "" // Key=Value per line
    @State private var urlString: String = ""
    
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
                Button("Add Agent") {
                    addAgent()
                }
                .disabled(name.isEmpty || (transportType == .stdio && command.isEmpty) || (transportType == .sse && urlString.isEmpty))
                
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }
        }
        .padding()
        .frame(width: 400, height: 500)
    }
    
    private func addAgent() {
        var config = MCPServerConfig(
            name: name,
            transportType: transportType
        )
        
        if transportType == .stdio {
            config.command = command
            // Simple argument parsing (splitting by space, respecting quotes would be better but keeping simple)
            config.arguments = arguments.split(separator: " ").map(String.init)
            
            var envDict: [String: String] = [:]
            environment.enumerateLines { line, _ in
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    envDict[String(parts[0])] = String(parts[1])
                }
            }
            config.environment = envDict
        } else {
            config.url = URL(string: urlString)
        }
        
        manager.addConfig(config)
        dismiss()
    }
}
