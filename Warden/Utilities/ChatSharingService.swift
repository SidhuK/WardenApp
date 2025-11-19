

import Foundation
import SwiftUI
import AppKit

enum ChatExportFormat: String, CaseIterable {
    case plainText = "Plain Text"
    case markdown = "Markdown"
    case json = "JSON"
    
    var fileExtension: String {
        switch self {
        case .plainText: return "txt"
        case .markdown: return "md"
        case .json: return "json"
        }
    }
}

class ChatSharingService {
    static let shared = ChatSharingService()
    
    private init() {}
    
    /// Share a chat using macOS native sharing service
    func shareChat(_ chat: ChatEntity, format: ChatExportFormat = .markdown) {
        let content = formatChatForExport(chat, format: format)
        let filename = "\(chat.name).\(format.fileExtension)"
        
        // Create a temporary file
        let tempURL = createTemporaryFile(content: content, filename: filename)
        
        // Use NSSharingService to share
        let sharingServicePicker = NSSharingServicePicker(items: [tempURL])
        
        // Get the key window to position the sharing picker
        if let window = NSApp.keyWindow {
            let rect = NSRect(x: window.frame.midX - 100, y: window.frame.midY, width: 200, height: 50)
            sharingServicePicker.show(relativeTo: rect, of: window.contentView!, preferredEdge: .minY)
        }
    }
    
    /// Share chat directly with text content (for copy/paste scenarios)
    func shareChatAsText(_ chat: ChatEntity, format: ChatExportFormat = .markdown) -> String {
        return formatChatForExport(chat, format: format)
    }
    
    /// Copy chat to clipboard
    func copyChatToClipboard(_ chat: ChatEntity, format: ChatExportFormat = .markdown) {
        let content = formatChatForExport(chat, format: format)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
    }
    
    /// Export chat to file with save dialog
    func exportChatToFile(_ chat: ChatEntity, format: ChatExportFormat = .markdown) {
        let content = formatChatForExport(chat, format: format)
        let filename = "\(chat.name).\(format.fileExtension)"
        
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        savePanel.allowedContentTypes = [.plainText, .data]
        savePanel.title = "Export Chat"
        savePanel.message = "Choose where to save the chat export"
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Error saving chat export: \(error)")
                    // Show error alert
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Export Failed"
                        alert.informativeText = "Could not save the chat export: \(error.localizedDescription)"
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func formatChatForExport(_ chat: ChatEntity, format: ChatExportFormat) -> String {
        switch format {
        case .plainText:
            return formatAsPlainText(chat)
        case .markdown:
            return formatAsMarkdown(chat)
        case .json:
            return formatAsJSON(chat)
        }
    }
    
    private func formatAsPlainText(_ chat: ChatEntity) -> String {
        var content = """
        Chat: \(chat.name)
        Created: \(formatDate(chat.createdDate))
        Updated: \(formatDate(chat.updatedDate))
        Model: \(chat.gptModel)
        
        """
        
        if !chat.systemMessage.isEmpty {
            content += """
            System Message:
            \(chat.systemMessage)
            
            ---
            
            """
        }
        
        let messages = chat.messagesArray.sorted { 
            ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) 
        }
        
        for message in messages {
            let sender = message.own ? "You" : "Assistant"
            let timestamp = formatDate(message.timestamp ?? Date())
            
            content += """
            [\(timestamp)] \(sender):
            \(message.body)
            
            """
        }
        
        return content
    }
    
    private func formatAsMarkdown(_ chat: ChatEntity) -> String {
        var content = """
        # \(chat.name)
        
        **Created:** \(formatDate(chat.createdDate))  
        **Updated:** \(formatDate(chat.updatedDate))  
        **Model:** \(chat.gptModel)
        
        """
        
        if !chat.systemMessage.isEmpty {
            content += """
            ## System Message
            
            > \(chat.systemMessage)
            
            ---
            
            """
        }
        
        let messages = chat.messagesArray.sorted { 
            ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) 
        }
        
        for message in messages {
            let sender = message.own ? "**You**" : "**Assistant**"
            let timestamp = formatDate(message.timestamp ?? Date())
            
            content += """
            ### \(sender) (\(timestamp))
            
            \(message.body)
            
            """
        }
        
        return content
    }
    
    private func formatAsJSON(_ chat: ChatEntity) -> String {
        let legacyChat = ChatBackup(chatEntity: chat)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(legacyChat)
            return String(data: data, encoding: .utf8) ?? "Error encoding chat data"
        } catch {
            return "Error encoding chat data: \(error.localizedDescription)"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func createTemporaryFile(content: String, filename: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(filename)
        
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)
        
        return tempURL
    }
} 
