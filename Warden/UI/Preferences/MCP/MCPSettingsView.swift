import SwiftUI

struct MCPSettingsView: View {
    @StateObject private var manager = MCPManager.shared
    @State private var showingAddSheet = false
    @State private var selectedConfig: MCPServerConfig?
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Model Context Protocol Agents")
                    .font(.headline)
                Spacer()
                Button(action: {
                    showingAddSheet = true
                }) {
                    Label("Add Agent", systemImage: "plus")
                }
            }
            .padding(.bottom)
            
            if manager.configs.isEmpty {
                Text("No agents configured. Add an agent to extend capabilities.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($manager.configs) { $config in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(config.name)
                                    .font(.headline)
                                Text(config.transportType == .stdio ? "Stdio: \(config.command ?? "")" : "SSE: \(config.url?.absoluteString ?? "")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedConfig = config
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $config.enabled)
                                .onChange(of: config.enabled) { newValue in
                                    manager.updateConfig(config)
                                }
                                .toggleStyle(.switch)
                        }
                        .padding(.vertical, 4)
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
            }
        }
        .padding()
        .sheet(isPresented: $showingAddSheet) {
            AddMCPAgentSheet(manager: manager, configToEdit: nil)
        }
        .sheet(item: $selectedConfig) { config in
            AddMCPAgentSheet(manager: manager, configToEdit: config)
        }
    }
}
