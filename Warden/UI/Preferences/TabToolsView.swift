import SwiftUI

struct TabToolsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case webSearch = "Web Search"
        case mcpAgents = "MCP Agents"
        
        var id: String { rawValue }
    }
    
    @State private var selectedSection: Section = .webSearch
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            switch selectedSection {
            case .webSearch:
                TabTavilySearchView()
            case .mcpAgents:
                MCPSettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview {
    TabToolsView()
        .frame(width: 800, height: 600)
}
#endif
