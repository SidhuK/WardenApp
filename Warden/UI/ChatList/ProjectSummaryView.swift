import SwiftUI
import CoreData

struct ProjectSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var store: ChatStore
    
    @ObservedObject var project: ProjectEntity
    @State private var isRefreshingSummary = false
    
    private var projectColor: Color {
        Color(hex: project.colorCode ?? "#007AFF") ?? .accentColor
    }
    
    private var projectChats: [ChatEntity] {
        guard let chats = project.chats?.allObjects as? [ChatEntity] else { return [] }
        return chats.sorted { $0.updatedDate > $1.updatedDate }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Project header
                    projectHeader
                    
                    // Quick stats
                    projectStats
                    
                    // AI Summary section
                    summarySection
                    
                    // Key insights (if available)
                    if hasInsights {
                        insightsSection
                    }
                    
                    // Recent activity
                    recentActivitySection
                    
                    Spacer(minLength: 100)
                }
                .padding(24)
            }
            .navigationTitle("Project Overview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        refreshSummary()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                    }
                    .disabled(isRefreshingSummary || projectChats.isEmpty)
                }
            }
        }
        .frame(width: 700, height: 800)
    }
    
    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(projectColor)
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name ?? "Untitled Project")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    if let description = project.projectDescription, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if project.isArchived {
                    Label("Archived", systemImage: "archivebox")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.orange.opacity(0.1))
                        )
                }
            }
            
            HStack(spacing: 16) {
                Label("Created \(project.createdAt ?? Date(), style: .date)", systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let lastSummary = project.lastSummarizedAt {
                    Label("Updated \(lastSummary, style: .relative)", systemImage: "doc.text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(projectColor.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(projectColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var projectStats: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Chats",
                value: "\(projectChats.count)",
                icon: "message",
                color: .blue
            )
            
            StatCard(
                title: "Messages",
                value: "\(totalMessages)",
                icon: "text.bubble",
                color: .green
            )
            
            StatCard(
                title: "Days Active",
                value: "\(daysActive)",
                icon: "clock",
                color: .orange
            )
            
            if let lastActivity = projectChats.first?.updatedDate {
                StatCard(
                    title: "Last Activity",
                    value: relativeDateString(lastActivity),
                    icon: "clock.arrow.circlepath",
                    color: .purple
                )
            }
        }
    }
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI Summary")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if isRefreshingSummary {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if let summary = project.aiGeneratedSummary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(summary)
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundColor(.primary)
                    
                    if let lastSummary = project.lastSummarizedAt {
                        Text("Generated \(lastSummary, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            } else {
                EmptyStateView(
                    icon: "doc.text",
                    title: "No Summary Available",
                    description: projectChats.isEmpty ? 
                        "Add some chats to this project to generate an AI summary." :
                        "Click \"Refresh\" to generate an AI summary of this project.",
                    action: projectChats.isEmpty ? nil : ("Generate Summary", refreshSummary)
                )
            }
        }
    }
    
    private var hasInsights: Bool {
        // This would be expanded when we have more sophisticated analysis
        project.aiGeneratedSummary != nil && !projectChats.isEmpty
    }
    
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Insights")
                .font(.title2)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                InsightCard(
                    title: "Most Active Period",
                    value: mostActivePeriod,
                    icon: "chart.line.uptrend.xyaxis",
                    color: .blue
                )
                
                InsightCard(
                    title: "Average Message Length",
                    value: "\(averageMessageLength) chars",
                    icon: "textformat.size",
                    color: .green
                )
                
                InsightCard(
                    title: "Conversation Style",
                    value: conversationStyle,
                    icon: "person.2",
                    color: .purple
                )
                
                InsightCard(
                    title: "Project Focus",
                    value: projectFocus,
                    icon: "target",
                    color: .orange
                )
            }
        }
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.title2)
                .fontWeight(.semibold)
            
            if projectChats.isEmpty {
                EmptyStateView(
                    icon: "message",
                    title: "No Chats Yet",
                    description: "This project doesn't have any chats yet.",
                    action: nil
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(projectChats.prefix(5)), id: \.objectID) { chat in
                        RecentChatRow(chat: chat)
                    }
                    
                    if projectChats.count > 5 {
                        HStack {
                            Text("And \(projectChats.count - 5) more chat\(projectChats.count - 5 == 1 ? "" : "s")...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var totalMessages: Int {
        projectChats.reduce(0) { total, chat in
            total + chat.messagesArray.count
        }
    }
    
    private var daysActive: Int {
        guard let firstChat = projectChats.last?.createdDate else { return 0 }
        let lastActivity = projectChats.first?.updatedDate ?? Date()
        return Calendar.current.dateComponents([.day], from: firstChat, to: lastActivity).day ?? 0
    }
    
    private var mostActivePeriod: String {
        // Simple implementation - could be enhanced with actual analysis
        if daysActive < 7 {
            return "This week"
        } else if daysActive < 30 {
            return "Recent weeks"
        } else {
            return "Over time"
        }
    }
    
    private var averageMessageLength: Int {
        let totalChars = projectChats.flatMap { $0.messagesArray }.reduce(0) { total, message in
            total + message.body.count
        }
        return totalMessages > 0 ? totalChars / totalMessages : 0
    }
    
    private var conversationStyle: String {
        let avgLength = averageMessageLength
        if avgLength < 50 {
            return "Brief & Direct"
        } else if avgLength < 200 {
            return "Conversational"
        } else {
            return "Detailed"
        }
    }
    
    private var projectFocus: String {
        // This could be enhanced with NLP analysis of chat content
        if let instructions = project.customInstructions, !instructions.isEmpty {
            if instructions.lowercased().contains("code") {
                return "Development"
            } else if instructions.lowercased().contains("research") {
                return "Research"
            } else if instructions.lowercased().contains("writing") {
                return "Writing"
            }
        }
        return "General"
    }
    
    // MARK: - Helper Methods
    
    private func relativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func refreshSummary() {
        isRefreshingSummary = true
        
        Task {
            await MainActor.run {
                store.generateProjectSummary(project)
                isRefreshingSummary = false
            }
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct InsightCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Spacer()
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct RecentChatRow: View {
    @ObservedObject var chat: ChatEntity
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "message")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if let lastMessage = chat.lastMessage {
                    Text(lastMessage.body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(chat.updatedDate, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("\(chat.messagesArray.count) msg")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    let action: (String, () -> Void)?
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if let (actionTitle, actionHandler) = action {
                Button(actionTitle, action: actionHandler)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

// MARK: - Extensions

extension TimeInterval {
    var days: Int {
        return Int(self / (24 * 60 * 60))
    }
}

#Preview {
    if let project = PreviewStateManager.shared.sampleProject {
        ProjectSummaryView(project: project)
            .environmentObject(PreviewStateManager.shared.chatStore)
            .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
    } else {
        Text("No sample project available")
    }
} 