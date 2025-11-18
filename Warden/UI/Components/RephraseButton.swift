
import SwiftUI
import CoreData

struct RephraseButton: View {
    @Binding var text: String
    var chat: ChatEntity?
    var onRephraseStart: () -> Void
    var onRephraseComplete: () -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var rephraseService = RephraseService()
    @State private var originalText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(text: Binding<String>, chat: ChatEntity?, onRephraseStart: @escaping () -> Void = {}, onRephraseComplete: @escaping () -> Void = {}) {
        self._text = text
        self.chat = chat
        self.onRephraseStart = onRephraseStart
        self.onRephraseComplete = onRephraseComplete
    }
    
    private var canRephrase: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
        chat?.apiService != nil && 
        !rephraseService.isRephrasing
    }
    
    var body: some View {
        Button(action: {
            rephraseText()
        }) {
            HStack(spacing: 6) {
                if rephraseService.isRephrasing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(canRephrase ? .accentColor : .secondary)
                }
                
                if !rephraseService.isRephrasing {
                    Text("Rephrase")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(canRephrase ? .accentColor : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(canRephrase ? Color.accentColor.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                canRephrase ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2),
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .help(rephraseService.isRephrasing ? "Rephrasing..." : "Rephrase for clarity")
        .disabled(!canRephrase)
        .opacity(canRephrase ? 1.0 : 0.6)
        .alert("Rephrase Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func rephraseText() {
        guard let apiService = chat?.apiService else {
            showError("No AI service selected. Please select an AI service first.")
            return
        }
        
        // Store original text if this is the first rephrase
        if originalText.isEmpty {
            originalText = text
        }
        
        onRephraseStart()
        
        rephraseService.rephraseText(text, using: apiService) { [self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let rephrasedText):
                    // Animate the text change
                    withAnimation(.easeInOut(duration: 0.3)) {
                        text = rephrasedText
                    }
                    onRephraseComplete()
                    
                case .failure(let error):
                    var errorText = "Failed to rephrase text"
                    
                    switch error {
                    case .unauthorized:
                        errorText = "Invalid API key. Please check your API settings."
                    case .rateLimited:
                        errorText = "Rate limit exceeded. Please try again later."
                    case .serverError(let message):
                        errorText = "Server error: \(message)"
                    case .noApiService(let message):
                        errorText = message
                    default:
                        errorText = "Rephrase failed: \(error.localizedDescription)"
                    }
                    
                    showError(errorText)
                    onRephraseComplete()
                }
            }
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

#Preview {
    @Previewable @State var sampleText = "Hello, this is a test message that needs rephrasing."
    
    return RephraseButton(text: $sampleText, chat: nil)
        .padding()
} 
