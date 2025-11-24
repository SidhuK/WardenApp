import SwiftUI

struct MCPAgentSelector: View {
    @ObservedObject var manager = MCPManager.shared
    @Binding var selectedAgents: Set<UUID>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Agents")
                .font(.headline)
            
            Divider()
            
            if manager.configs.isEmpty {
                Text("No agents configured.")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Button("Configure Agents...") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenPreferences"),
                        object: nil,
                        userInfo: ["tab": "mcp"]
                    )
                }
                .buttonStyle(.link)
                .font(.caption)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(manager.configs) { config in
                            Toggle(isOn: Binding(
                                get: { selectedAgents.contains(config.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedAgents.insert(config.id)
                                    } else {
                                        selectedAgents.remove(config.id)
                                    }
                                }
                            )) {
                                HStack {
                                    Text(config.name)
                                        .foregroundColor(config.enabled ? .primary : .secondary)
                                    Spacer()
                                    Image(systemName: config.transportType == .stdio ? "terminal" : "network")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                            .disabled(!config.enabled)
                            .help(config.enabled ? "Enable for this chat" : "Agent is disabled in settings")
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding()
        .frame(width: 250)
    }
}
