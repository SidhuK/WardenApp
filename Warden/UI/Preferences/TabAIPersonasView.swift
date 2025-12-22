import CoreData
import SwiftUI
import UniformTypeIdentifiers
import os

struct TabAIPersonasView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.order, ascending: true)],
        animation: .default
    )
    private var personas: FetchedResults<PersonaEntity>

    @State private var isShowingAddOrEditPersona = false
    @State private var selectedPersona: PersonaEntity?
    @State private var selectedPersonaID: NSManagedObjectID?
    @State private var refreshID = UUID()
    @State private var showingDeleteConfirmation = false
    @State private var personaToDelete: PersonaEntity?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Assistants")
                        .font(.system(size: 24, weight: .bold))
                    Text("Create custom AI personas with unique behaviors")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                
                // Personas List
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            SettingsSectionHeader(title: "Your Assistants", icon: "person.2.fill", iconColor: .blue)
                            
                            Spacer()
                            
                            if personas.isEmpty {
                                Button {
                                    DatabasePatcher.addDefaultPersonasIfNeeded(context: viewContext, force: true)
                                } label: {
                                    Label("Add Presets", systemImage: "plus.circle")
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 12))
                            }
                        }
                        
                        entityListView
                            .id(refreshID)
                            .frame(minHeight: 200)
                        
                        SettingsDivider()
                        
                        HStack(spacing: 12) {
                            if selectedPersonaID != nil {
                                Button {
                                    onEdit()
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .buttonStyle(.bordered)
                                .keyboardShortcut(.defaultAction)

                                Button(role: .destructive) {
                                    if let persona = personas.first(where: { $0.objectID == selectedPersonaID }) {
                                        personaToDelete = persona
                                        showingDeleteConfirmation = true
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            Spacer()
                            
                            Button {
                                onAdd()
                            } label: {
                                Label("New Assistant", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                
                // Tips
                GlassCard(padding: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.yellow)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tip: Custom System Messages")
                                .font(.system(size: 12, weight: .medium))
                            Text("Define how your assistant should behave, its tone, expertise, and response style.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .onChange(of: selectedPersonaID) { _, id in
            selectedPersona = personas.first(where: { $0.objectID == id })
        }
        .sheet(isPresented: $isShowingAddOrEditPersona) {
            PersonaDetailView(
                persona: $selectedPersona,
                onSave: { refreshList() },
                onDelete: { selectedPersona = nil }
            )
        }
        .alert("Delete Assistant", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let persona = personaToDelete {
                    viewContext.delete(persona)
                    try? viewContext.save()
                    selectedPersonaID = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(personaToDelete?.name ?? "")\"?")
        }
    }

    private var entityListView: some View {
        EntityListView(
            selectedEntityID: $selectedPersonaID,
            entities: personas,
            detailContent: detailContent,
            onRefresh: refreshList,
            getEntityColor: { _ in nil },
            getEntityName: getPersonaName,
            getEntityIcon: getPersonaSymbol,
            onEdit: {
                if let persona = personas.first(where: { $0.objectID == selectedPersonaID }) {
                    selectedPersona = persona
                    isShowingAddOrEditPersona = true
                }
            },
            onMove: { fromOffsets, toOffset in
                var updatedItems = Array(personas)
                updatedItems.move(fromOffsets: fromOffsets, toOffset: toOffset)
                for (index, item) in updatedItems.enumerated() {
                    item.order = Int16(index)
                }
                do {
                    try viewContext.save()
                } catch {
                    WardenLog.coreData.error(
                        "Failed to save reordering: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        )
    }

    private func detailContent(persona: PersonaEntity?) -> some View {
        Group {
            if let persona = persona {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        Text(persona.systemMessage ?? "")
                            .font(.system(size: 12))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.03))
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Temperature: \(String(format: "%.1f", persona.temperature))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        
                        if let defaultService = persona.defaultApiService {
                            HStack(spacing: 4) {
                                Image("logo_\(defaultService.type ?? "")")
                                    .resizable()
                                    .renderingMode(.template)
                                    .frame(width: 10, height: 10)
                                    .foregroundStyle(.secondary)
                                Text("\(defaultService.name ?? "") • \(defaultService.model ?? "")")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Uses global default service")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } else {
                VStack(spacing: 8) {
                    if personas.isEmpty {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("No assistants yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Create one or add from presets")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Select an assistant")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.02))
                )
            }
        }
    }

    private func onAdd() {
        selectedPersona = nil
        isShowingAddOrEditPersona = true
    }

    private func onEdit() {
        selectedPersona = personas.first(where: { $0.objectID == selectedPersonaID })
        isShowingAddOrEditPersona = true
    }

    private func getPersonaSymbol(persona: PersonaEntity) -> String? {
        return persona.color ?? "person.circle"
    }

    private func getPersonaName(persona: PersonaEntity) -> String {
        persona.name ?? "Unnamed"
    }

    private func refreshList() {
        refreshID = UUID()
    }
}


// MARK: - Persona Detail View
struct PersonaDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    @Binding var persona: PersonaEntity?
    let onSave: () -> Void
    let onDelete: () -> Void

    @State private var name: String = ""
    @State private var selectedSymbol: String = "person.circle"
    @State private var systemMessage: String = ""
    @State private var temperature: Double = 0.7
    @State private var selectedApiService: APIServiceEntity?
    @State private var showingDeleteConfirmation = false

    let symbols = [
        "person.circle", "person.circle.fill", "person.2.circle", "person.2.circle.fill",
        "brain.head.profile", "brain", "lightbulb", "lightbulb.fill",
        "star.circle", "star.circle.fill", "heart.circle", "heart.circle.fill",
        "gear.circle", "gear.circle.fill", "book.circle", "book.circle.fill",
        "graduationcap.circle", "graduationcap.circle.fill", "briefcase.circle", "briefcase.circle.fill",
        "paintbrush.pointed", "paintbrush.pointed.fill", "music.note", "music.note.list",
        "camera.circle", "camera.circle.fill", "gamecontroller.circle", "gamecontroller.circle.fill",
        "wrench.and.screwdriver", "hammer", "stethoscope", "cross.case",
        "leaf.circle", "leaf.circle.fill", "globe", "globe.americas",
        "airplane.circle", "airplane.circle.fill", "car.circle", "car.circle.fill"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            Text(persona == nil ? "New Assistant" : "Edit Assistant")
                .font(.system(size: 18, weight: .semibold))

            // Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Assistant name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Symbol
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 10), spacing: 6) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            selectedSymbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 16))
                                .foregroundStyle(selectedSymbol == symbol ? .white : .primary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(selectedSymbol == symbol ? Color.accentColor : Color.primary.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // System Message
            VStack(alignment: .leading, spacing: 6) {
                Text("System Message")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                MessageInputView(
                    text: $systemMessage,
                    attachedImages: .constant([]),
                    attachedFiles: .constant([]),
                    webSearchEnabled: .constant(false),
                    selectedMCPAgents: .constant([]),
                    chat: nil,
                    imageUploadsAllowed: false,
                    isStreaming: false,
                    isMultiAgentMode: .constant(false),
                    selectedMultiAgentServices: .constant([]),
                    showServiceSelector: .constant(false),
                    enableMultiAgentMode: false,
                    onEnter: {},
                    onAddImage: {},
                    onAddFile: {},
                    onStopStreaming: {},
                    inputPlaceholderText: "Define how this assistant should behave...",
                    cornerRadius: 8
                )
            }

            // Temperature
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Temperature")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(getTemperatureLabel())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.05))
                        )
                }
                
                HStack {
                    Text("0.0")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Slider(value: $temperature, in: 0...1, step: 0.1)
                    Text("1.0")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            // Default Service
            VStack(alignment: .leading, spacing: 6) {
                Text("Default AI Service")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                HStack {
                    Picker("", selection: $selectedApiService) {
                        Text("Use global default").tag(nil as APIServiceEntity?)
                        ForEach(apiServices, id: \.self) { service in
                            Text("\(service.name ?? "Unknown") • \(service.model ?? "")")
                                .tag(service as APIServiceEntity?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    
                    if selectedApiService != nil {
                        Button {
                            selectedApiService = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            // Actions
            HStack {
                if persona != nil {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.bordered)

                Button(persona == nil ? "Create" : "Save") {
                    savePersona()
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || systemMessage.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 620)
        .onAppear {
            if let persona = persona {
                name = persona.name ?? ""
                selectedSymbol = persona.color ?? "person.circle"
                systemMessage = persona.systemMessage ?? ""
                temperature = Double(persona.temperature)
                selectedApiService = persona.defaultApiService
            }
        }
        .alert("Delete Assistant", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deletePersona()
                onDelete()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func getTemperatureLabel() -> String {
        if temperature > 0.8 { return "Creative" }
        if temperature > 0.6 { return "Explorative" }
        if temperature > 0.4 { return "Balanced" }
        if temperature > 0.2 { return "Focused" }
        return "Deterministic"
    }

    private func savePersona() {
        let personaToSave = persona ?? PersonaEntity(context: viewContext)
        personaToSave.name = name
        personaToSave.color = selectedSymbol
        personaToSave.temperature = Float(round(temperature * 10) / 10)
        personaToSave.systemMessage = systemMessage
        personaToSave.defaultApiService = selectedApiService
        
        if persona == nil {
            personaToSave.addedDate = Date()
            personaToSave.id = UUID()

            let fetchRequest: NSFetchRequest<PersonaEntity> = PersonaEntity.fetchRequest()
            do {
                let existingPersonas = try viewContext.fetch(fetchRequest)
                for existingPersona in existingPersonas {
                    existingPersona.order += 1
                }
                personaToSave.order = 0
            } catch {
                personaToSave.order = 0
            }
        } else {
            personaToSave.editedDate = Date()
        }

        do {
            personaToSave.objectWillChange.send()
            try viewContext.save()
            presentationMode.wrappedValue.dismiss()
        } catch {
            let nsError = error as NSError
            WardenLog.coreData.error("Failed to save persona: \(nsError.localizedDescription, privacy: .public)")
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Failed to Save"
                alert.informativeText = nsError.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func deletePersona() {
        if let personaToDelete = persona {
            viewContext.delete(personaToDelete)
            do {
                try viewContext.save()
                presentationMode.wrappedValue.dismiss()
            } catch {
                let nsError = error as NSError
                WardenLog.coreData.error("Failed to delete persona: \(nsError.localizedDescription, privacy: .public)")
            }
        }
    }
}

#Preview {
    TabAIPersonasView()
        .frame(width: 600, height: 600)
}
