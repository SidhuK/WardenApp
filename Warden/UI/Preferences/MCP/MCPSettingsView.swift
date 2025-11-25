import SwiftUI
import MCP

struct MCPSettingsView: View {
    @StateObject private var manager = MCPManager.shared
    @State private var showingAddSheet = false
    @State private var selectedConfig: MCPServerConfig?
    
    var body: some View {
        MasterDetailLayout(masterWidth: 280) {
            // Sidebar
            VStack(spacing: 0) {
                // Header
                GlassToolbar {
                    HStack {
                        Text("MCP Agents")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Button {
                                Task { await manager.restartAll() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.borderless)
                            .help("Restart All")
                            
                            Button {
                                showingAddSheet = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderless)
                            .help("Add Agent")
                        }
                    }
                }
                
                // List
                if manager.configs.isEmpty {
                    GlassEmptyState(
                        icon: "server.rack",
                        title: "No Agents",
                        subtitle: "Add an MCP agent to get started"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(manager.configs) { config in
                                MCPAgentRow(
                                    config: config,
                                    status: manager.serverStatuses[config.id] ?? .disconnected,
                                    isSelected: selectedConfig?.id == config.id
                                ) {
                                    selectedConfig = config
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
        } detail: {
            // Detail
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
                GlassEmptyState(
                    icon: "server.rack",
                    title: "Select an Agent",
                    subtitle: "Choose an MCP agent from the sidebar to view details"
                )
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddMCPAgentSheet(manager: manager, configToEdit: nil)
        }
    }
}

// MARK: - Agent Row

struct MCPAgentRow: View {
    let config: MCPServerConfig
    let status: MCPManager.ServerStatus
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .secondary
        case .error: return .red
        case .connecting: return .orange
        }
    }
    
    var body: some View {
        GlassListRow(
            icon: config.transportType == .stdio ? "terminal.fill" : "network",
            title: config.name,
            subtitle: statusText,
            isSelected: isSelected,
            badge: config.enabled ? nil : "OFF",
            badgeColor: .secondary,
            action: onSelect
        )
        .overlay(alignment: .leading) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .offset(x: 6)
        }
    }
    
    private var statusText: String {
        switch status {
        case .connected(let count): return "\(count) tools"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        case .connecting: return "Connecting..."
        }
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
    @State private var showingDeleteConfirmation = false
    
    private var status: MCPManager.ServerStatus {
        manager.serverStatuses[config.id] ?? .disconnected
    }
    
    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .secondary
        case .error: return .red
        case .connecting: return .orange
        }
    }
    
    private var statusText: String {
        switch status {
        case .connected(let count): return "Connected • \(count) tools"
        case .disconnected: return "Disconnected"
        case .error(let msg): return "Error: \(msg)"
        case .connecting: return "Connecting..."
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(statusColor.opacity(0.15))
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
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $config.enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                // Quick Actions
                GlassCard(padding: 12) {
                    HStack(spacing: 12) {
                        ActionButton(
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
                        
                        ActionButton(
                            title: "Test",
                            icon: isTesting ? "hourglass" : "bolt.fill",
                            color: .blue,
                            isLoading: isTesting
                        ) {
                            testConnection()
                        }
                        .disabled(isTesting)
                        
                        ActionButton(title: "Edit", icon: "pencil", color: .secondary) {
                            showingEditSheet = true
                        }
                        
                        ActionButton(title: "Restart", icon: "arrow.clockwise", color: .secondary) {
                            Task {
                                await manager.disconnect(id: config.id)
                                try? await manager.connect(config: config)
                            }
                        }
                    }
                }
                
                // Test Result
                if let result = testResult {
                    HStack(spacing: 8) {
                        Image(systemName: result.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.contains("Success") ? .green : .red)
                        Text(result)
                            .font(.system(size: 12))
                            .foregroundStyle(result.contains("Success") ? .green : .red)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(result.contains("Success") ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    )
                }
                
                // Configuration
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(title: "Configuration", icon: "gearshape.fill", iconColor: .gray)
                        
                        VStack(spacing: 12) {
                            ConfigRow(label: "Transport", value: config.transportType == .stdio ? "Stdio" : "SSE", icon: "network")
                            
                            if config.transportType == .stdio {
                                if let command = config.command {
                                    ConfigRow(label: "Command", value: command, icon: "terminal")
                                }
                                if !config.arguments.isEmpty {
                                    ConfigRow(label: "Arguments", value: config.arguments.joined(separator: " "), icon: "text.alignleft")
                                }
                                if !config.environment.isEmpty {
                                    ConfigRow(label: "Environment", value: "\(config.environment.count) variables", icon: "key")
                                }
                            } else {
                                if let url = config.url {
                                    ConfigRow(label: "URL", value: url.absoluteString, icon: "link")
                                }
                            }
                        }
                    }
                }
                
                // Tools
                ToolsSection(
                    tools: manager.serverTools[config.id] ?? [],
                    status: status,
                    onRefresh: {
                        Task { _ = await manager.getToolsForServer(id: config.id) }
                    }
                )
                
                // Delete
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Agent", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .sheet(isPresented: $showingEditSheet) {
            AddMCPAgentSheet(manager: manager, configToEdit: config)
        }
        .alert("Delete Agent", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("Are you sure you want to delete \"\(config.name)\"?")
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

// MARK: - Supporting Views

struct ActionButton: View {
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
        .onHover { isHovered = $0 }
    }
}

struct ConfigRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
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
        .padding(.vertical, 4)
    }
}

struct ToolsSection: View {
    let tools: [Tool]
    let status: MCPManager.ServerStatus
    let onRefresh: () -> Void
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SettingsSectionHeader(
                        title: "Available Tools",
                        icon: "wrench.and.screwdriver.fill",
                        iconColor: .blue
                    )
                    
                    if !tools.isEmpty {
                        Text("(\(tools.count))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if case .connected = status {
                        Button {
                            onRefresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh")
                    }
                }
                
                if case .disconnected = status {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "bolt.slash")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                            Text("Connect to view tools")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                } else if tools.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                            Text("No tools available")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(tools.enumerated()), id: \.element.name) { index, tool in
                            ToolRow(tool: tool)
                            if index < tools.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ToolRow: View {
    let tool: Tool
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wrench.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                        .frame(width: 20)
                    
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
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Input Schema")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(tool.inputSchema.description)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 100)
                }
                .padding(.leading, 32)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview {
    MCPSettingsView()
        .frame(width: 800, height: 600)
}
