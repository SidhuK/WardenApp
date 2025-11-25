import SwiftUI
import MCP

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
    @State private var showingEditSheet = false
    
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
        case .connected(let count): return "Connected • \(count) tools available"
        case .disconnected: return "Disconnected"
        case .error(let msg): return "Error: \(msg)"
        case .connecting: return "Connecting..."
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Card
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        // Agent Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [statusColor.opacity(0.2), statusColor.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 52, height: 52)
                            
                            Image(systemName: config.transportType == .stdio ? "terminal.fill" : "network")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(statusColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(config.name)
                                .font(.system(size: 20, weight: .semibold))
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 8, height: 8)
                                Text(statusText)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $config.enabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    // Quick Actions
                    HStack(spacing: 10) {
                        DetailActionButton(
                            title: status == .disconnected ? "Connect" : "Disconnect",
                            icon: status == .disconnected ? "power" : "stop.fill",
                            color: status == .disconnected ? .green : .orange
                        ) {
                            Task {
                                if case .connected = status {
                                    await manager.disconnect(id: config.id)
                                } else {
                                    try? await manager.connect(config: config)
                                }
                            }
                        }
                        
                        DetailActionButton(
                            title: "Test",
                            icon: isTesting ? "arrow.trianglehead.2.counterclockwise" : "bolt.fill",
                            color: .blue,
                            isLoading: isTesting
                        ) {
                            testConnection()
                        }
                        .disabled(isTesting)
                        
                        DetailActionButton(
                            title: "Edit",
                            icon: "pencil",
                            color: .secondary
                        ) {
                            showingEditSheet = true
                        }
                        
                        DetailActionButton(
                            title: "Restart",
                            icon: "arrow.clockwise",
                            color: .secondary
                        ) {
                            Task {
                                await manager.disconnect(id: config.id)
                                try? await manager.connect(config: config)
                            }
                        }
                    }
                    
                    if let result = testResult {
                        HStack(spacing: 8) {
                            Image(systemName: result.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.contains("Success") ? .green : .red)
                            Text(result)
                                .font(.system(size: 12))
                                .foregroundColor(result.contains("Success") ? .green : .red)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(result.contains("Success") ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        )
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                
                // Configuration Details
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Configuration")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    
                    VStack(spacing: 0) {
                        DetailRow(
                            label: "Transport",
                            value: config.transportType == .stdio ? "Stdio (Local Process)" : "SSE (Server-Sent Events)",
                            icon: config.transportType == .stdio ? "terminal" : "network"
                        )
                        
                        Divider().padding(.leading, 40)
                        
                        if config.transportType == .stdio {
                            DetailRow(
                                label: "Command",
                                value: config.command ?? "Not set",
                                icon: "chevron.right"
                            )
                            
                            if !config.arguments.isEmpty {
                                Divider().padding(.leading, 40)
                                DetailRow(
                                    label: "Arguments",
                                    value: config.arguments.joined(separator: " "),
                                    icon: "text.alignleft"
                                )
                            }
                            
                            if !config.environment.isEmpty {
                                Divider().padding(.leading, 40)
                                DetailRow(
                                    label: "Environment",
                                    value: "\(config.environment.count) variable(s)",
                                    icon: "key"
                                )
                            }
                        } else {
                            DetailRow(
                                label: "URL",
                                value: config.url?.absoluteString ?? "Not set",
                                icon: "link"
                            )
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                
                // Available Tools Section
                ToolListView(
                    tools: manager.serverTools[config.id] ?? [],
                    status: status,
                    onRefresh: {
                        Task {
                            _ = await manager.getToolsForServer(id: config.id)
                        }
                    }
                )
                
                Spacer()
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingEditSheet) {
            AddMCPAgentSheet(manager: manager, configToEdit: config)
        }
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

// MARK: - Detail Supporting Views

struct DetailActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isLoading: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .foregroundStyle(isHovered ? color : .secondary)
                .frame(width: 20, height: 20)
                
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? color.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Tool List View

struct ToolListView: View {
    let tools: [Tool]
    let status: MCPManager.ServerStatus
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Available Tools")
                    .font(.system(size: 13, weight: .semibold))
                
                if !tools.isEmpty {
                    Text("(\(tools.count))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if case .connected = status {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh Tools")
                }
            }
            
            if case .disconnected = status {
                // Disconnected state
                VStack(spacing: 8) {
                    Image(systemName: "bolt.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Connect to view tools")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
            } else if tools.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No tools available")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
            } else {
                // Tools list
                VStack(spacing: 8) {
                    ForEach(Array(tools.enumerated()), id: \.element.name) { index, tool in
                        ToolItemView(tool: tool)
                        
                        if index < tools.count - 1 {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
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
}

struct ToolItemView: View {
    let tool: Tool
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "wrench.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        
                        if let description = tool.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(isExpanded ? nil : 1)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Input Schema")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        
                        ScrollView {
                            Text(formatSchema(tool.inputSchema))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func formatSchema(_ schema: Value) -> String {
        // Simply use the description property which should provide JSON-like output
        return schema.description
    }
}
