import SwiftUI

struct MCPSettingsView: View {
    @StateObject private var manager = MCPManager.shared
    @State private var showingAddSheet = false
    @State private var selectedConfig: MCPServerConfig?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Model Context Protocol Agents")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: {
                    showingAddSheet = true
                }) {
                    Label("Add Agent", systemImage: "plus")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            if manager.configs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No agents configured")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Add an MCP agent to extend capabilities with external tools.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                List {
                    ForEach($manager.configs) { $config in
                        MCPAgentRow(config: $config, manager: manager)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedConfig = config
                            }
                            .contextMenu {
                                Button("Edit") {
                                    selectedConfig = config
                                }
                                Button("Delete", role: .destructive) {
                                    manager.deleteConfig(id: config.id)
                                }
                            }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            manager.deleteConfig(id: manager.configs[index].id)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddMCPAgentSheet(manager: manager, configToEdit: nil)
        }
        .sheet(item: $selectedConfig) { config in
            AddMCPAgentSheet(manager: manager, configToEdit: config)
        }
    }
}

struct MCPAgentRow: View {
    @Binding var config: MCPServerConfig
    @ObservedObject var manager: MCPManager
    
    var status: MCPManager.ServerStatus {
        manager.serverStatuses[config.id] ?? .disconnected
    }
    
    var statusColor: Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .gray
        case .error: return .red
        case .connecting: return .orange
        }
    }
    
    var statusText: String {
        switch status {
        case .connected(let count): return "Connected (\(count) tools)"
        case .disconnected: return "Disconnected"
        case .error(let msg): return "Error: \(msg)"
        case .connecting: return "Connecting..."
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Dot
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.4), radius: 2, x: 0, y: 0)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(config.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                
                HStack(spacing: 8) {
                    Label(config.transportType == .stdio ? "Stdio" : "SSE", systemImage: config.transportType == .stdio ? "terminal" : "network")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(status == .disconnected ? .secondary : statusColor)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $config.enabled)
                .onChange(of: config.enabled) { newValue in
                    manager.updateConfig(config)
                }
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}
