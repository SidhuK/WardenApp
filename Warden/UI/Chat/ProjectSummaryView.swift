import SwiftUI
import CoreData

struct ProjectSummaryView: View {
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
        ScrollView {
            VStack(alignment: .center, spacing: 32) {
                // Centered project header
                centeredProjectHeader
                
                // AI Summary section
                summarySection
                
                // Recent activity
                recentActivitySection
                
                // Bottom compact cards - Stats and Insights
                bottomCompactSection
                
                Spacer(minLength: 100)
            }
            .padding(24)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text(project.name ?? "Project Summary")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    refreshSummary()
                }) {
                    HStack(spacing: 4) {
                        if isRefreshingSummary {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh")
                    }
                }
                .disabled(isRefreshingSummary || projectChats.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var centeredProjectHeader: some View {
        VStack(alignment: .center, spacing: 16) {
            // Project icon centered
            Image(systemName: "folder.fill")
                .font(.system(size: 48))
                .foregroundColor(projectColor)
            
            VStack(alignment: .center, spacing: 8) {
                Text(project.name ?? "Untitled Project")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                if let description = project.projectDescription, !description.isEmpty {
                    Text(description)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            HStack(spacing: 20) {
                Label("Created \(project.createdAt ?? Date(), style: .date)", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let lastSummary = project.lastSummarizedAt {
                    Label("Last Summary \(lastSummary, style: .date)", systemImage: "doc.text")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if project.isArchived {
                    Label("Archived", systemImage: "archivebox")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.orange.opacity(0.1))
                        )
                }
            }
        }
    }
    
    private var bottomCompactSection: some View {
        HStack(alignment: .top, spacing: 16) {
            // Stats Card
            compactStatsCard
            
            // Insights Card
            if hasInsights {
                compactInsightsCard
            }
        }
    }
    
    private var compactStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text("Project Stats")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Chats:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(projectChats.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Messages:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(totalMessages)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Days Active:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(daysActive)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                if let lastActivity = projectChats.first?.updatedDate {
                    HStack {
                        Text("Last Activity:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatDateString(lastActivity))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var compactInsightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                Text("Key Insights")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Style:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(conversationStyle)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Focus:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(projectFocus)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Activity:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(mostActivePeriod)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Avg. Length:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(averageMessageLength) chars")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text("Generated \(lastSummary, style: .date)")
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
                ProjectEmptyStateView(
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
        project.aiGeneratedSummary != nil && !projectChats.isEmpty
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                ForEach(Array(projectChats.prefix(5)), id: \.objectID) { chat in
                    Button(action: {
                        // Post notification to select the chat
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SelectChatFromProjectSummary"),
                            object: chat
                        )
                    }) {
                        HStack {
                            // AI Model Logo (same as regular chats) - aligned with proper padding
                            Image("logo_\(chat.apiService?.type ?? "")")
                                .resizable()
                                .renderingMode(.template)
                                .interpolation(.high)
                                .frame(width: 16, height: 16)
                                .foregroundColor(.primary)
                                .padding(.leading, 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chat.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                                
                                if let lastMessage = chat.lastMessage {
                                    Text(lastMessage.body)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer()
                            
                            Text(chat.updatedDate, style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.clear, lineWidth: 2)
                    )
                }
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
        guard let firstActivity = projectChats.last?.createdDate,
              let lastActivity = projectChats.first?.updatedDate else {
            return 0
        }
        return Calendar.current.dateComponents([.day], from: firstActivity, to: lastActivity).day ?? 0
    }
    
    private var mostActivePeriod: String {
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
    
    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
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

private struct ProjectEmptyStateView: View {
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
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if let action = action {
                Button(action: action.1) {
                    Text(action.0)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

#Preview {
    if let sampleProject = PreviewStateManager.shared.sampleProject {
        ProjectSummaryView(project: sampleProject)
            .environmentObject(PreviewStateManager.shared.chatStore)
            .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
    } else {
        Text("No sample project available")
    }
} 