
import CommonCrypto
import CoreData
import Foundation
import SwiftUI

extension Data {
    public func sha256() -> String {
        return hexStringFromData(input: digest(input: self as NSData))
    }

    private func digest(input: NSData) -> NSData {
        let digestLength = Int(CC_SHA256_DIGEST_LENGTH)
        var hash = [UInt8](repeating: 0, count: digestLength)
        CC_SHA256(input.bytes, UInt32(input.length), &hash)
        return NSData(bytes: hash, length: digestLength)
    }

    private func hexStringFromData(input: NSData) -> String {
        var bytes = [UInt8](repeating: 0, count: input.length)
        input.getBytes(&bytes, length: input.length)

        var hexString = ""
        for byte in bytes {
            hexString += String(format: "%02x", UInt8(byte))
        }

        return hexString
    }
}

extension Date {
    func formattedTimestamp() -> String {
        let formatter = DateFormatter()
        let now = Date()
        let calendar = Calendar.current
        
        // Check if it's today
        if calendar.isDate(self, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: self)
        }
        
        // Check if it's yesterday
        if calendar.isDate(self, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now) {
            formatter.dateFormat = "HH:mm"
            return "Yesterday \(formatter.string(from: self))"
        }
        
        // Check if it's within the current week
        let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        if self > weekAgo {
            formatter.dateFormat = "E HH:mm"
            return formatter.string(from: self)
        }
        
        // For older messages, show date and time
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: self)
    }
}

extension String {
    public func sha256() -> String {
        if let stringData = self.data(using: String.Encoding.utf8) {
            return stringData.sha256()
        }
        return ""
    }
}

extension NSManagedObjectContext {
    func saveWithRetry(attempts: Int) {
        do {
            try self.save()
        }
        catch {
            print("Core Data save failed: \(error)")

            self.rollback()

            if attempts > 0 {
                print("Retrying save operation...")
                self.saveWithRetry(attempts: attempts - 1)
            }
            else {
                print("Failed to save after multiple attempts")
            }
        }
    }
}

extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
    
    func chatFont(size: Double) -> some View {
        self.font(.system(size: size, weight: .regular))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        edges.map { edge -> Path in
            switch edge {
            case .top: return Path(.init(x: rect.minX, y: rect.minY, width: rect.width, height: width))
            case .bottom: return Path(.init(x: rect.minX, y: rect.maxY - width, width: rect.width, height: width))
            case .leading: return Path(.init(x: rect.minX, y: rect.minY, width: width, height: rect.height))
            case .trailing: return Path(.init(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height))
            }
        }.reduce(into: Path()) { $0.addPath($1) }
    }
}

extension Binding {
    func equalTo<A: Equatable>(_ value: A) -> Binding<Bool> where Value == A? {
        Binding<Bool> {
            wrappedValue == value
        } set: {
            if $0 {
                wrappedValue = value
            }
            else if wrappedValue == value {
                wrappedValue = nil
            }
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }

    func toHex() -> String {
        let components = self.cgColor?.components
        let r: CGFloat = components?[0] ?? 0.0
        let g: CGFloat = components?[1] ?? 0.0
        let b: CGFloat = components?[2] ?? 0.0

        let hexString = String.init(
            format: "#%02lX%02lX%02lX",
            lroundf(Float(r * 255)),
            lroundf(Float(g * 255)),
            lroundf(Float(b * 255))
        )

        return hexString
    }

}

extension Double {
    func toInt16() -> Int16? {
        guard self >= Double(Int16.min) && self <= Double(Int16.max) else {
            return nil
        }
        return Int16(self)
    }
}

extension Int16 {
    var toDouble: Double {
        return Double(self)
    }
}

extension Float {
    func roundedToOneDecimal() -> Float {
        return (self * 10).rounded() / 10
    }
}

extension PersistenceController {
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        let chat = ChatEntity(context: viewContext)
        chat.id = UUID()
        chat.name = "Sample Chat"
        chat.createdDate = Date()
        chat.updatedDate = Date()
        chat.gptModel = AppConstants.chatGptDefaultModel

        let persona = PersonaEntity(context: viewContext)
        persona.name = "Assistant"
        persona.color = "person.circle"
        chat.persona = persona

        try? viewContext.save()
        return result
    }()
}

extension ChatEntity {
    func constructRequestMessages(forUserMessage userMessage: String?, contextSize: Int) -> [[String: String]] {
        var messages: [[String: String]] = []

        // Build comprehensive system message with project context
        let systemMessage = buildSystemMessageWithProjectContext()
        
        #if DEBUG
        print("🤖 Persona: \(self.persona?.name ?? "None")")
        print("🗂️ Project: \(self.project?.name ?? "None")")
        print("📝 System Message: \(systemMessage)")
        #endif

        if !AppConstants.openAiReasoningModels.contains(self.gptModel) {
            messages.append([
                "role": "system",
                "content": systemMessage,
            ])
        }
        else {
            // Models like o1-mini and o1-preview don't support "system" role. However, we can pass the system message with "user" role instead.
            messages.append([
                "role": "user",
                "content": "Take this message as the system message: \(systemMessage)",
            ])
        }

        let orderedMessages = self.messagesArray
        let historyMessages: [MessageEntity]
        if contextSize <= 0 {
            historyMessages = []
        } else if orderedMessages.count > contextSize {
            historyMessages = Array(orderedMessages.suffix(contextSize))
        } else {
            historyMessages = orderedMessages
        }

        // Add conversation history
        for message in historyMessages {
            messages.append([
                "role": message.own ? "user" : "assistant",
                "content": message.body,
            ])
        }

        // Add new user message if provided
        let lastMessage = messages.last?["content"] ?? ""
        if lastMessage != userMessage {
            if let userMessage = userMessage {
                messages.append([
                    "role": "user",
                    "content": userMessage,
                ])
            }
        }

        return messages
    }
    
    /// Builds a comprehensive system message that includes project context, project instructions, and persona instructions
    /// Uses clear delimiters and hierarchy for better AI comprehension
    /// Handles instruction precedence: project-specific > project context > base instructions
    private func buildSystemMessageWithProjectContext() -> String {
        var sections: [String] = []
        
        // Section 1: Base System Instructions (general behavior)
        let baseSystemMessage = self.persona?.systemMessage ?? self.systemMessage
        if !baseSystemMessage.isEmpty {
            sections.append("""
            === BASE INSTRUCTIONS ===
            \(baseSystemMessage)
            ========================
            """)
        }
        
        // Section 2: Project Context (if applicable)
        if let project = self.project {
            // Provide basic project info
            let projectInfo = """
            
            PROJECT CONTEXT:
            You are working within the "\(project.name ?? "Untitled Project")" project.
            """
            if let description = project.projectDescription, !description.isEmpty {
                sections.append(projectInfo + " Project description: \(description)")
            } else {
                sections.append(projectInfo)
            }
            
            // Section 3: Project-specific custom instructions
            if let customInstructions = project.customInstructions, !customInstructions.isEmpty {
                let projectInstructions = """
                
                PROJECT-SPECIFIC INSTRUCTIONS:
                \(customInstructions)
                """
                sections.append(projectInstructions)
            }
        }
        
        // Combine all components into final system message
        return sections.joined(separator: "\n")
    }
}

struct PreviewHTMLGenerator {
    static func generate(content: String, colorScheme: ColorScheme, device: PreviewPane.DeviceType) -> String {
        // Inject modern CSS framework and styling with responsive meta tag
        let modernCSS = AppConstants.getModernCSS(
            isMobile: device == .mobile,
            isTablet: device == .tablet,
            isDark: colorScheme == .dark
        )
        
        // Enhanced meta viewport for device simulation
        let viewportMeta = AppConstants.viewportMeta
        
        // If the content already has HTML structure, inject our CSS and viewport
        if content.lowercased().contains("<html") ||
           content.lowercased().contains("<!doctype") {
            var modifiedContent = content
            
            // Add viewport meta tag
            if let headRange = modifiedContent.range(of: "<head>", options: .caseInsensitive) {
                let insertionPoint = modifiedContent.index(headRange.upperBound, offsetBy: 0)
                modifiedContent.insert(contentsOf: "\n    \(viewportMeta)", at: insertionPoint)
            }
            
            // Add CSS
            if let headEndRange = modifiedContent.range(of: "</head>", options: .caseInsensitive) {
                modifiedContent.insert(contentsOf: modernCSS, at: headEndRange.lowerBound)
            }
            
            return modifiedContent
        }
        
        // Otherwise, wrap content in full HTML structure
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            \(viewportMeta)
            <title>HTML Preview - \(device.rawValue)</title>
            \(modernCSS)
        </head>
        <body>
            \(content)
        </body>
        </html>
        """
    }
}

