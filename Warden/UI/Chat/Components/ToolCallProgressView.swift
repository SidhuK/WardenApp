import SwiftUI

struct ToolCallProgressView: View {
    let toolCalls: [ToolCallStatus]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
                
                Text("Tool Calls")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("(\(toolCalls.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            
            VStack(spacing: 6) {
                ForEach(toolCalls) { status in
                    ToolCallRow(status: status)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ToolCallRow: View {
    let status: ToolCallStatus
    
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
                HStack(spacing: 10) {
                    statusIcon
                        .frame(width: 20, height: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedToolName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text(statusText)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if hasResult {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasResult)
            
            if isExpanded, let result = status.result {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.horizontal, 10)
                    
                    ScrollView {
                        Text(formatResult(result))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(resultBackgroundColor)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isExpanded)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .calling:
            ProgressView()
                .scaleEffect(0.55)
        case .executing:
            ProgressView()
                .scaleEffect(0.55)
        case .completed(_, let success, _):
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(
                    LinearGradient(
                        colors: success ? [.green, .green.opacity(0.8)] : [.red, .red.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .font(.system(size: 14))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .orange.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .font(.system(size: 14))
        }
    }
    
    private var formattedToolName: String {
        status.toolName
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
    
    private var statusText: String {
        switch status {
        case .calling:
            return "Calling..."
        case .executing(_, let progress):
            return progress ?? "Executing..."
        case .completed(_, let success, _):
            return success ? "Completed" : "Failed"
        case .failed(_, let error):
            return "Error: \(error)"
        }
    }
    
    private var backgroundColor: Color {
        switch status {
        case .calling, .executing:
            return Color.orange.opacity(0.08)
        case .completed(_, let success, _):
            return success ? Color.green.opacity(0.08) : Color.red.opacity(0.08)
        case .failed:
            return Color.red.opacity(0.08)
        }
    }
    
    private var resultBackgroundColor: Color {
        switch status {
        case .completed(_, let success, _):
            return success ? Color.green.opacity(0.04) : Color.red.opacity(0.04)
        case .failed:
            return Color.red.opacity(0.04)
        default:
            return Color.clear
        }
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
    let toolCalls: [ToolCallStatus]
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                    
                    Text("\(toolCalls.count) tool\(toolCalls.count == 1 ? "" : "s") used")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(toolCalls) { status in
                        ToolCallRow(status: status)
                    }
                }
                .padding(.top, 8)
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
