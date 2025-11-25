import SwiftUI

struct MCPSettingsView: View {
    @StateObject private var manager = MCPManager.shared
    @State private var showingAddSheet = false
    @State private var selectedConfig: MCPServerConfig?
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar - MCP Agents List
            VStack(spacing: 0) {
                // Sidebar Header
                HStack {
                    Text("MCP Agents")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Agents List
                if manager.configs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No agents")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(manager.configs) { config in
                                MCPAgentSidebarRow(
                                    config: config,
                                    status: manager.serverStatuses[config.id] ?? .disconnected,
                                    isSelected: selectedConfig?.id == config.id
                                ) {
                                    selectedConfig = config
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                Divider()
                
                // Bottom Actions
                HStack(spacing: 12) {
                    Button(action: {
                        showingAddSheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("Add New Agent")
                    
                    Button(action: {
                        Task {
                            await manager.restartAll()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("Restart All Agents")
                    
                    Spacer()
                    
                    if let config = selectedConfig {
                        Button(action: {
                            manager.deleteConfig(id: config.id)
                            selectedConfig = nil
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Delete Agent")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(width: 250)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Right Side - Agent Details
            Group {
                if let config = selectedConfig {
                    MCPAgentDetailView(
                        config: Binding(
                            get: { config },
                            set: { newValue in
                                manager.updateConfig(newValue)
                                selectedConfig = newValue
                            }
                        ),
                        manager: manager,
                        onDelete: {
                            manager.deleteConfig(id: config.id)
                            selectedConfig = nil
                        }
                    )
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("Select an agent")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Choose an MCP agent from the sidebar to view details, or add a new one.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddMCPAgentSheet(manager: manager, configToEdit: nil)
        }
    }
}

// MARK: - Sidebar Row

struct MCPAgentSidebarRow: View {
    let config: MCPServerConfig
    let status: MCPManager.ServerStatus
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .gray
        case .error: return .red
        case .connecting: return .orange
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                // Agent info
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(config.transportType == .stdio ? "Stdio" : "SSE")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Enabled indicator
                if config.enabled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

// MARK: - Detail View

struct MCPAgentDetailView: View {
    @Binding var config: MCPServerConfig
    @ObservedObject var manager: MCPManager
    let onDelete: () -> Void
    
    @State private var isTesting = false
    @State private var testResult: String?
    
    private var status: MCPManager.ServerStatus {
        manager.serverStatuses[config.id] ?? .disconnected
    }
    
    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .gray
        case .error: return .red
        case .connecting: return .orange
        }
    }
    
    private var statusText: String {
        switch status {
        case .connected(let count): return "Connected (\(count) tools)"
        case .disconnected: return "Disconnected"
        case .error(let msg): return "Error: \(msg)"
        case .connecting: return "Connecting..."
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(config.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(statusText)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Toggle("Enabled", isOn: $config.enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                Divider()
                
                // Configuration Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Configuration")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    // Transport Type
                    HStack {
                        Text("Transport:")
                        Spacer()
                        Text(config.transportType == .stdio ? "Stdio (Local Process)" : "SSE (Server-Sent Events)")
                            .foregroundColor(.secondary)
                    }
                    
                    if config.transportType == .stdio {
                        // Command
                        HStack {
                            Text("Command:")
                            Spacer()
                            Text(config.command ?? "Not set")
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        // Arguments
                        if !config.arguments.isEmpty {
                            HStack(alignment: .top) {
                                Text("Arguments:")
                                Spacer()
                                Text(config.arguments.joined(separator: " "))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        
                        // Environment
                        if !config.environment.isEmpty {
                            HStack(alignment: .top) {
                                Text("Environment:")
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    ForEach(Array(config.environment.keys.sorted()), id: \.self) { key in
                                        Text("\(key)=***")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        // URL
                        HStack {
                            Text("URL:")
                            Spacer()
                            Text(config.url?.absoluteString ?? "Not set")
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Divider()
                
                // Actions Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Actions")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 12) {
                        Button(action: testConnection) {
                            HStack {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "bolt.fill")
                                }
                                Text("Test Connection")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isTesting)
                        
                        Button(action: {
                            Task {
                                if case .connected = status {
                                    await manager.disconnect(id: config.id)
                                } else {
                                    try? await manager.connect(config: config)
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: status == .disconnected ? "power" : "stop.fill")
                                Text(status == .disconnected ? "Connect" : "Disconnect")
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                    
                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.contains("Success") ? .green : .red)
                            .padding(.top, 4)
                    }
                }
                
                Spacer()
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        Task {
            do {
                let toolCount = try await manager.testConnection(config: config)
                await MainActor.run {
                    testResult = "Success! Found \(toolCount) tools."
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "Failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}
