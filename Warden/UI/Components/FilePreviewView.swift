import SwiftUI

struct FilePreviewView: View {
    @ObservedObject var attachment: FileAttachment
    let onRemove: (Int) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(attachment.fileType.color.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                // Content overlay
                VStack(spacing: 4) {
                    if attachment.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if let error = attachment.error {
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                                .font(.title2)
                            Text("Error")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        .help(error.localizedDescription)
                    } else {
                        switch attachment.fileType {
                        case .image:
                            if let thumbnail = attachment.thumbnail {
                                Image(nsImage: thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 76, height: 76)
                                    .clipped()
                                    .cornerRadius(6)
                            } else {
                                Image(systemName: attachment.fileType.icon)
                                    .foregroundColor(attachment.fileType.color)
                                    .font(.title)
                            }
                        case .pdf:
                            if let thumbnail = attachment.thumbnail {
                                Image(nsImage: thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .clipped()
                                    .cornerRadius(4)
                            } else {
                                Image(systemName: attachment.fileType.icon)
                                    .foregroundColor(attachment.fileType.color)
                                    .font(.title)
                            }
                        default:
                            Image(systemName: attachment.fileType.icon)
                                .foregroundColor(attachment.fileType.color)
                                .font(.title)
                        }
                    }
                }
                
                // Remove button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            onRemove(0) // We'll need to pass the actual index
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.primary)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(Circle())
                                .font(.caption)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                }
                .padding(4)
            }
            
            // File name and info
            VStack(spacing: 2) {
                Text(attachment.fileName)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                
                if attachment.fileSize > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: attachment.fileSize, countStyle: .file))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 80)
        }
        .help(getFileTooltip())
    }
    
    private func getFileTooltip() -> String {
        var tooltip = "\(attachment.fileName)"
        
        if attachment.fileSize > 0 {
            tooltip += "\nSize: \(ByteCountFormatter.string(fromByteCount: attachment.fileSize, countStyle: .file))"
        }
        
        switch attachment.fileType {
        case .text:
            tooltip += "\nText file"
        case .csv:
            tooltip += "\nCSV file - Click to view data"
        case .pdf:
            tooltip += "\nPDF document - Text will be extracted"
        case .json:
            tooltip += "\nJSON file - Structure will be analyzed"
        case .xml:
            tooltip += "\nXML file - Structure will be analyzed"
        case .markdown:
            tooltip += "\nMarkdown file"
        case .rtf:
            tooltip += "\nRich text file"
        case .image:
            tooltip += "\nImage file"
        case .other(let ext):
            tooltip += "\n\(ext.uppercased()) file"
        }
        
        if !attachment.textContent.isEmpty {
            let contentPreview = String(attachment.textContent.prefix(100))
            tooltip += "\n\nPreview: \(contentPreview)..."
        }
        
        return tooltip
    }
}

struct FilePreviewView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            // CSV file preview
            FilePreviewView(
                attachment: {
                    let attachment = FileAttachment(url: URL(fileURLWithPath: "/tmp/data.csv"))
                    attachment.fileName = "sales_data.csv"
                    attachment.fileSize = 15420
                    attachment.fileType = .csv
                    attachment.textContent = "Name,Age,City\nJohn,25,NYC\nJane,30,LA"
                    attachment.isLoading = false
                    return attachment
                }(),
                onRemove: { _ in }
            )
            
            // PDF file preview
            FilePreviewView(
                attachment: {
                    let attachment = FileAttachment(url: URL(fileURLWithPath: "/tmp/report.pdf"))
                    attachment.fileName = "quarterly_report.pdf"
                    attachment.fileSize = 2457600
                    attachment.fileType = .pdf
                    attachment.textContent = "Q4 Financial Report..."
                    attachment.isLoading = false
                    return attachment
                }(),
                onRemove: { _ in }
            )
            
            // Text file preview
            FilePreviewView(
                attachment: {
                    let attachment = FileAttachment(url: URL(fileURLWithPath: "/tmp/notes.txt"))
                    attachment.fileName = "meeting_notes.txt"
                    attachment.fileSize = 3456
                    attachment.fileType = .text
                    attachment.textContent = "Meeting Notes\n\n1. Discuss project timeline\n2. Review budget"
                    attachment.isLoading = false
                    return attachment
                }(),
                onRemove: { _ in }
            )
        }
        .padding()
    }
} 

extension FileAttachmentType {
    var icon: String {
        switch self {
        case .image: return "photo"
        case .text: return "doc.text"
        case .csv: return "tablecells"
        case .pdf: return "doc.richtext"
        case .json: return "doc.badge.gearshape"
        case .xml: return "doc.badge.ellipsis"
        case .markdown: return "doc.text"
        case .rtf: return "doc.richtext"
        case .other: return "doc"
        }
    }

    var color: Color {
        switch self {
        case .image: return .blue
        case .text: return .gray
        case .csv: return .green
        case .pdf: return .red
        case .json: return .orange
        case .xml: return .purple
        case .markdown: return .blue
        case .rtf: return .brown
        case .other: return .secondary
        }
    }

    var displayName: String {
        switch self {
        case .image: return "Image"
        case .text: return "Text"
        case .csv: return "CSV"
        case .pdf: return "PDF"
        case .json: return "JSON"
        case .xml: return "XML"
        case .markdown: return "Markdown"
        case .rtf: return "RTF"
        case .other(let ext): return ext.uppercased()
        }
    }
}
