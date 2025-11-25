import SwiftUI

struct ToolCallProgressView: View {
    let toolCalls: [ToolCallStatus]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.orange)
                
                Text("Tool Calls")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            ForEach(Array(toolCalls.enumerated()), id: \.offset) { index, status in
                ToolCallRow(status: status)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ToolCallRow: View {
    let status: ToolCallStatus
    
    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            statusIcon
                .frame(width: 18, height: 18)
            
            // Tool name and status
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedToolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .calling:
            ProgressView()
                .scaleEffect(0.6)
        case .executing:
            ProgressView()
                .scaleEffect(0.6)
        case .completed(_, let success):
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(success ? .green : .red)
                .font(.system(size: 14))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))
        }
    }
    
    private var formattedToolName: String {
        // Convert snake_case to Title Case
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
        case .completed(_, let success):
            return success ? "Completed" : "Failed"
        case .failed(_, let error):
            return "Error: \(error)"
        }
    }
    
    private var backgroundColor: Color {
        switch status {
        case .calling, .executing:
            return Color.orange.opacity(0.1)
        case .completed(_, let success):
            return success ? Color.green.opacity(0.1) : Color.red.opacity(0.1)
        case .failed:
            return Color.red.opacity(0.1)
        }
    }
}

// MARK: - Preview

struct ToolCallProgressView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            ToolCallProgressView(toolCalls: [
                .calling(toolName: "search_notion"),
                .executing(toolName: "get_page", progress: "Fetching page content..."),
                .completed(toolName: "list_databases", success: true),
                .failed(toolName: "update_page", error: "Permission denied")
            ])
        }
        .padding()
        .frame(width: 400)
    }
}
