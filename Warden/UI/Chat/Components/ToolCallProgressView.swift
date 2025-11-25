import SwiftUI

struct ToolCallProgressView: View {
    let toolCalls: [WardenToolCallStatus]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Text("Tool Calls")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                if !toolCalls.isEmpty {
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    
                    Text("\(toolCalls.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            VStack(spacing: 1) {
                ForEach(toolCalls) { status in
                    ToolCallRow(status: status)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}

struct ToolCallRow: View {
    let status: WardenToolCallStatus
    
    @State private var isExpanded = false
    
    private var hasResult: Bool {
        status.result != nil && !status.result!.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if hasResult {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    statusIcon
                        .frame(width: 14, height: 14)
                    
                    Text(formattedToolName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if hasResult {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasResult)
            
            if isExpanded, let result = status.result {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .opacity(0.5)
                    
                    ScrollView {
                        Text(formatResult(result))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isExpanded)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .calling, .executing:
            ProgressView()
                .scaleEffect(0.4)
        case .completed(_, let success, _):
            Image(systemName: success ? "checkmark.circle" : "xmark.circle")
                .foregroundStyle(success ? .green : .red)
                .font(.system(size: 11))
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.system(size: 11))
        }
    }
    
    private var formattedToolName: String {
        status.toolName
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
    
    private func formatResult(_ result: String) -> String {
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 1000 {
            return String(trimmed.prefix(1000)) + "\n... (truncated)"
        }
        return trimmed
    }
}

// MARK: - Completed Tool Calls View (for persisted tool calls with messages)

struct CompletedToolCallsView: View {
    let toolCalls: [WardenToolCallStatus]
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text("\(toolCalls.count) tool\(toolCalls.count == 1 ? "" : "s") used")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(toolCalls) { status in
                        ToolCallRow(status: status)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isExpanded)
    }
}

// MARK: - Preview

struct ToolCallProgressView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            ToolCallProgressView(toolCalls: [
                .calling(toolName: "search_notion"),
                .executing(toolName: "get_page", progress: "Fetching page content..."),
                .completed(toolName: "list_databases", success: true, result: "{\"databases\": [{\"id\": \"abc123\", \"title\": \"My Database\"}]}"),
                .failed(toolName: "update_page", error: "Permission denied")
            ])
            
            Divider()
            
            CompletedToolCallsView(toolCalls: [
                .completed(toolName: "search_notion", success: true, result: "{\"results\": []}"),
                .completed(toolName: "get_page", success: true, result: "{\"content\": \"Page content here\"}")
            ])
        }
        .padding()
        .frame(width: 400)
    }
}
