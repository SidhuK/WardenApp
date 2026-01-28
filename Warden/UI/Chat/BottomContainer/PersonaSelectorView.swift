
import CoreData
import SwiftUI

struct PersonaChipView: View {
    let persona: PersonaEntity
    let isSelected: Bool
    @State private var isHovered = false

    private let personaSymbol: String

    init(persona: PersonaEntity, isSelected: Bool) {
        self.persona = persona
        self.isSelected = isSelected
        self.personaSymbol = persona.color ?? "person.circle"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: personaSymbol)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
            
            Text(persona.name ?? "")
                .foregroundStyle(.primary)
        }
        .frame(height: 32)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .opacity(isSelected ? 0.8 : 0.3)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor, lineWidth: isSelected ? 2 : 0)
                )
                .shadow(
                    color: .accentColor.opacity(isSelected ? 0.3 : (isHovered ? 0.1 : 0)),
                    radius: isSelected ? 4 : 2
                )
        )
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
        .padding(4)
    }
}

struct PersonaSelectorView: View {
    enum SortMode {
        case order
        case addedDate
    }

    @FetchRequest private var personas: FetchedResults<PersonaEntity>

    private let edgeDarkColor = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    private let edgeLightColor = Color.white

    @ObservedObject var chat: ChatEntity
    let showsNoneChip: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(
        chat: ChatEntity,
        showsNoneChip: Bool = true,
        sortMode: SortMode = .order
    ) {
        self._chat = ObservedObject(wrappedValue: chat)
        self.showsNoneChip = showsNoneChip

        switch sortMode {
        case .order:
            self._personas = FetchRequest(
                sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.order, ascending: true)],
                animation: .default
            )
        case .addedDate:
            self._personas = FetchRequest(
                sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)],
                animation: .default
            )
        }
    }

    private func updatePersonaAndSystemMessage(to persona: PersonaEntity?) {
        chat.persona = persona
        
        // If the persona has a default API service configured, switch to it
        if let persona = persona, let defaultApiService = persona.defaultApiService {
            chat.apiService = defaultApiService
            chat.gptModel = defaultApiService.model ?? AppConstants.chatGptDefaultModel
            
            // Notify that the message manager needs to be recreated
            NotificationCenter.default.post(
                name: .recreateMessageManager,
                object: nil,
                userInfo: ["chatId": chat.id]
            )
        }
        
        chat.objectWillChange.send()

        if let context = chat.managedObjectContext {
            try? context.save()
        }
    }

    var body: some View {
        ScrollViewReader { scrollView in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if showsNoneChip {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                updatePersonaAndSystemMessage(to: nil)
                            }
                        } label: {
                            Text("None")
                                .foregroundStyle(.primary)
                                .frame(height: 32)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            chat.persona == nil
                                                ? Color.accentColor.opacity(0.6)
                                                : Color.gray.opacity(0.12)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(
                                                    chat.persona == nil
                                                        ? Color.accentColor.opacity(0.8)
                                                        : Color.gray.opacity(0.2),
                                                    lineWidth: chat.persona == nil ? 2 : 1
                                                )
                                        )
                                )
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("No persona")
                    }
                    
                    ForEach(personas, id: \.objectID) { persona in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                updatePersonaAndSystemMessage(to: persona)
                            }
                        } label: {
                            PersonaChipView(persona: persona, isSelected: chat.persona == persona)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(persona.name ?? "Persona"))
                        .id(persona.objectID)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [colorScheme == .dark ? edgeDarkColor : edgeLightColor, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(
                    colors: [.clear, colorScheme == .dark ? edgeDarkColor : edgeLightColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                .allowsHitTesting(false)
            }
            .onAppear {
                if let selectedPersonaID = chat.persona?.objectID {
                    scrollView.scrollTo(selectedPersonaID, anchor: .center)
                }
            }
        }
        .frame(height: 64)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let chat = ChatEntity(context: context)
    return PersonaSelectorView(chat: chat)
        .frame(width: 400)
}
