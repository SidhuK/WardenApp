import SwiftUI

struct AddMCPAgentSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var manager: MCPManager
    var configToEdit: MCPServerConfig?
    
    @State private var name: String = ""
    @State private var transportType: MCPServerConfig.TransportType = .stdio
    @State private var command: String = ""
    @State private var arguments: String = ""
    @State private var environment: String = ""
    @State private var urlString: String = ""
    
    @State private var testStatus: String? = nil
    @State private var isTesting: Bool = false
    
    private var isFormValid: Bool {
        !name.isEmpty && ((transportType == .stdio && !command.isEmpty) || (transportType == .sse && !urlString.isEmpty))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(configToEdit != nil ? "Edit MCP Agent" : "Add MCP Agent")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Configure a Model Context Protocol server")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // General Section
                    ConfigSection(title: "General", icon: "gearshape") {
                        VStack(alignment: .leading, spacing: 12) {
                            ConfigField(label: "Name", placeholder: "My MCP Agent", text: $name)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Transport Type")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                
                                HStack(spacing: 8) {
                                    TransportTypeButton(
                                        title: "Stdio",
                                        subtitle: "Local process",
                                        icon: "terminal",
                                        isSelected: transportType == .stdio
                                    ) {
                                        transportType = .stdio
                                    }
                                    
                                    TransportTypeButton(
                                        title: "SSE",
                                        subtitle: "Remote server",
                                        icon: "network",
                                        isSelected: transportType == .sse
                                    ) {
                                        transportType = .sse
                                    }
                                }
                            }
                        }
                    }
                    
                    // Configuration Section
                    if transportType == .stdio {
                        ConfigSection(title: "Command Configuration", icon: "terminal") {
                            VStack(alignment: .leading, spacing: 12) {
                                ConfigField(
                                    label: "Command",
                                    placeholder: "npx, uvx, node, etc.",
                                    text: $command
                                )
                                
                                ConfigField(
                                    label: "Arguments",
                                    placeholder: "-y @modelcontextprotocol/server-filesystem",
                                    text: $arguments
                                )
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Environment Variables")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    
                                    TextEditor(text: $environment)
                                        .font(.system(size: 13, design: .monospaced))
                                        .scrollContentBackground(.hidden)
                                        .padding(10)
                                        .frame(height: 100)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(nsColor: .textBackgroundColor))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                        )
                                        .overlay(alignment: .topLeading) {
                                            if environment.isEmpty {
                                                Text("KEY=VALUE (one per line)")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.secondary.opacity(0.6))
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 12)
                                                    .allowsHitTesting(false)
                                            }
                                        }
                                }
                            }
                        }
                    } else {
                        ConfigSection(title: "Network Configuration", icon: "network") {
                            ConfigField(
                                label: "Server URL",
                                placeholder: "http://localhost:3000/sse",
                                text: $urlString
                            )
                        }
                    }
                    
                    // Test Connection Section
                    ConfigSection(title: "Connection Test", icon: "bolt") {
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                testConnection()
                            } label: {
                                HStack(spacing: 8) {
                                    if isTesting {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 12))
                                    }
                                    Text("Test Connection")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentColor.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!isFormValid || isTesting)
                            .opacity(isFormValid ? 1 : 0.5)
                            
                            if let status = testStatus {
                                HStack(spacing: 8) {
                                    Image(systemName: status.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(status.contains("Success") ? .green : .red)
                                    Text(status)
                                        .font(.system(size: 12))
                                        .foregroundColor(status.contains("Success") ? .green : .red)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(status.contains("Success") ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                                )
                            }
                        }
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button {
                    saveAgent()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: configToEdit != nil ? "checkmark" : "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text(configToEdit != nil ? "Save Changes" : "Add Agent")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid || isTesting)
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 480, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let config = configToEdit {
                name = config.name
                transportType = config.transportType
                command = config.command ?? ""
                arguments = config.arguments.joined(separator: " ")
                environment = config.environment.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
                urlString = config.url?.absoluteString ?? ""
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

// MARK: - Supporting Views

struct ConfigSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            
            content
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }
}

struct ConfigField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

struct TransportTypeButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.05))
                    )
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
