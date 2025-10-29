import CoreData
import SwiftUI
import UniformTypeIdentifiers

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
            VStack(alignment: .leading, spacing: 16) {
                settingGroup {
                    VStack(spacing: 16) {
                        entityListView
                            .id(refreshID)
                            .frame(minHeight: 260)

                        Divider()

                        HStack(spacing: 20) {
                            if selectedPersonaID != nil {
                                Button(action: onEdit) {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .keyboardShortcut(.defaultAction)

                                Button(action: {
                                    if let persona = personas.first(where: { $0.objectID == selectedPersonaID }) {
                                        personaToDelete = persona
                                        showingDeleteConfirmation = true
                                    }
                                }) {
                                    Label("Delete", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .foregroundColor(Color.red)
                            }
                            Spacer()
                            if personas.isEmpty {
                                addPresetsButton
                            }
                            Button(action: onAdd) {
                                Label("Add New Assistant", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onChange(of: selectedPersonaID) { _, id in
            selectedPersona = personas.first(where: { $0.objectID == id })
        }
        .sheet(isPresented: $isShowingAddOrEditPersona) {
            PersonaDetailView(
                persona: $selectedPersona,
                onSave: {
                    refreshList()
                },
                onDelete: {
                    selectedPersona = nil
                }
            )
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Assistant \(personaToDelete?.name ?? "Unknown")"),
                message: Text("Are you sure you want to delete this assistant? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    if let persona = personaToDelete {
                        viewContext.delete(persona)
                        try? viewContext.save()
                        selectedPersonaID = nil
                    }
                },
                secondaryButton: .cancel()
            )
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
                }
                catch {
                    print("Failed to save reordering: \(error)")
                }
            }
        )
    }

    private var addPresetsButton: some View {
        Button(action: {
            DatabasePatcher.addDefaultPersonasIfNeeded(context: viewContext, force: true)
        }) {
            Label("Add Presets", systemImage: "plus.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private func detailContent(persona: PersonaEntity?) -> some View {
        Group {
            if let persona = persona {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        Text(persona.systemMessage ?? "")
                            .font(.callout)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.05))
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Temperature: \(String(format: "%.1f", persona.temperature))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let defaultService = persona.defaultApiService {
                            HStack {
                                Image("logo_\(defaultService.type ?? "")")
                                    .resizable()
                                    .renderingMode(.template)
                                    .frame(width: 12, height: 12)
                                    .foregroundColor(.accentColor)
                                Text("Default Service: \(defaultService.name ?? "Unknown") • \(defaultService.model ?? "No model")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Default Service: Uses global default")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            else {
                VStack(spacing: 8) {
                    if personas.isEmpty {
                        Text("No assistants found")
                            .font(.headline)
                        Text("Create one or add from presets")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    else {
                        Text("Select an assistant to view details")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
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
        persona.name ?? "Unnamed Assistant"
    }

    private func refreshList() {
        refreshID = UUID()
    }
    
    // MARK: - Section Header Style
    private func sectionHeader(icon: String, title: String, iconColor: Color = .accentColor, animate: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title2.weight(.semibold))
                .symbolEffect(.pulse, options: animate ? .repeating : .nonRepeating, value: animate)
                .frame(width: 30)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Material.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Setting Group Style
    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
    }
}

// MARK: - Inline Version for Main Window
struct InlineTabAIPersonasView: View {
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

    // Colors matching the chat app theme
    private let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    private var cardBackgroundColor: Color {
        Color(NSColor.controlBackgroundColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "person.2", title: "AI Assistants")
            
            settingGroup {
                VStack(spacing: 16) {
                    entityListView
                        .id(refreshID)
                        .frame(minHeight: 260)

                    Divider()

                    HStack(spacing: 20) {
                        if selectedPersonaID != nil {
                            Button(action: onEdit) {
                                Label("Edit", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .keyboardShortcut(.defaultAction)

                            Button(action: {
                                if let persona = personas.first(where: { $0.objectID == selectedPersonaID }) {
                                    personaToDelete = persona
                                    showingDeleteConfirmation = true
                                }
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .foregroundColor(Color.red)
                        }
                        Spacer()
                        if personas.isEmpty {
                            addPresetsButton
                        }
                        Button(action: onAdd) {
                            Label("Add New Assistant", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
            }
        }
        .onChange(of: selectedPersonaID) { _, id in
            selectedPersona = personas.first(where: { $0.objectID == id })
        }
        .sheet(isPresented: $isShowingAddOrEditPersona) {
            PersonaDetailView(
                persona: $selectedPersona,
                onSave: {
                    refreshList()
                },
                onDelete: {
                    selectedPersona = nil
                }
            )
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Assistant \(personaToDelete?.name ?? "Unknown")"),
                message: Text("Are you sure you want to delete this assistant? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    if let persona = personaToDelete {
                        viewContext.delete(persona)
                        try? viewContext.save()
                        selectedPersonaID = nil
                    }
                },
                secondaryButton: .cancel()
            )
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
                }
                catch {
                    print("Failed to save reordering: \(error)")
                }
            }
        )
    }

    private var addPresetsButton: some View {
        Button(action: {
            DatabasePatcher.addDefaultPersonasIfNeeded(context: viewContext, force: true)
        }) {
            Label("Add Presets", systemImage: "plus.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private func detailContent(persona: PersonaEntity?) -> some View {
        Group {
            if let persona = persona {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        Text(persona.systemMessage ?? "")
                            .font(.callout)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.05))
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Temperature: \(String(format: "%.1f", persona.temperature))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let defaultService = persona.defaultApiService {
                            HStack {
                                Image("logo_\(defaultService.type ?? "")")
                                    .resizable()
                                    .renderingMode(.template)
                                    .frame(width: 12, height: 12)
                                    .foregroundColor(.accentColor)
                                Text("Default Service: \(defaultService.name ?? "Unknown") • \(defaultService.model ?? "No model")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Default Service: Uses global default")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            else {
                VStack(spacing: 8) {
                    if personas.isEmpty {
                        Text("No assistants found")
                            .font(.headline)
                        Text("Create one or add from presets")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    else {
                        Text("Select an assistant to view details")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
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
        persona.name ?? "Unnamed Assistant"
    }

    private func refreshList() {
        refreshID = UUID()
    }
    
    // MARK: - Section Header Style
    private func sectionHeader(icon: String, title: String, iconColor: Color? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(iconColor ?? primaryBlue)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Setting Group Style
    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
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
        VStack(alignment: .leading, spacing: 16) {
            Text(persona == nil ? "Create New Assistant" : "Edit Assistant")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading) {
                Text("Name:")
                TextField("Assistant name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            VStack(alignment: .leading) {
                Text("Symbol:")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button(action: {
                            selectedSymbol = symbol
                        }) {
                            Image(systemName: symbol)
                                .font(.title2)
                                .foregroundColor(selectedSymbol == symbol ? .white : .primary)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(selectedSymbol == symbol ? Color.accentColor : Color.clear)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.secondary, lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            VStack(alignment: .leading) {
                Text("System message:")
                MessageInputView(
                    text: $systemMessage,
                    attachedImages: .constant([]),
                    attachedFiles: .constant([]),
                    webSearchEnabled: .constant(false),
                    chat: nil,
                    imageUploadsAllowed: false,
                    onEnter: {},
                    onAddImage: {},
                    onAddFile: {},
                    inputPlaceholderText: "Enter system message here",
                    cornerRadius: 4
                )
            }
            .padding(.top, 8)

            HStack {
                Slider(
                    value: $temperature,
                    in: 0...1,
                    step: 0.1
                ) {
                    Text("Temperature")
                } minimumValueLabel: {
                    Text("0.0")
                } maximumValueLabel: {
                    Text("1.0")
                }

                Text(getTemperatureLabel())
                    .frame(width: 90)
            }
            .padding(.top, 8)

            // Add API Service selection
            VStack(alignment: .leading) {
                Text("Default AI Service:")
                HStack {
                    Picker("Default AI Service", selection: $selectedApiService) {
                        Text("None (Use global default)").tag(nil as APIServiceEntity?)
                        ForEach(apiServices, id: \.self) { service in
                            Text("\(service.name ?? "Unknown") • \(service.model ?? "No model")")
                                .tag(service as APIServiceEntity?)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if selectedApiService != nil {
                        Button(action: {
                            selectedApiService = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Clear selection")
                    }
                }
                
                if selectedApiService != nil {
                    Text("When this assistant is selected, it will automatically use \(selectedApiService?.name ?? "this service") with the \(selectedApiService?.model ?? "configured model") model.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                } else {
                    Text("No specific service configured. Will use the global default API service when this assistant is selected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 8)

            HStack {
                if persona != nil {
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }

                Button(persona == nil ? "Create Assistant" : "Update Assistant") {
                    savePersona()
                    onSave()
                }
                .disabled(name.isEmpty || systemMessage.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)

        }
        .padding()
        .onAppear {
            print(">> Assistant: \(persona?.name ?? "")")
            if let persona = persona {
                name = persona.name ?? ""
                selectedSymbol = persona.color ?? "person.circle"
                systemMessage = persona.systemMessage ?? ""
                temperature = Double(persona.temperature)
                selectedApiService = persona.defaultApiService
            }
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Assistant"),
                message: Text("Are you sure you want to delete this assistant? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    deletePersona()
                    onDelete()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func getTemperatureLabel() -> String {
        if temperature > 0.8 {
            return "Creative"
        }

        if temperature > 0.6 {
            return "Explorative"
        }

        if temperature > 0.4 {
            return "Balanced"
        }

        if temperature > 0.2 {
            return "Focused"
        }

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
            }
            catch {
                personaToSave.order = 0
                print("Error fetching personas for order: \(error)")
            }
        }
        else {
            personaToSave.editedDate = Date()
        }

        do {
            personaToSave.objectWillChange.send()
            try viewContext.save()
            presentationMode.wrappedValue.dismiss()
        }
        catch {
            let nsError = error as NSError
            print("❌ Failed to save persona: \(nsError), \(nsError.userInfo)")
            
            // Show error to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Failed to Save Persona"
                alert.informativeText = "Could not save the persona changes. Error: \(nsError.localizedDescription)"
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
            }
            catch {
                let nsError = error as NSError
                print("❌ Failed to delete persona: \(nsError), \(nsError.userInfo)")
                
                // Show error to user
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Delete Persona"
                    alert.informativeText = "Could not delete the persona. Error: \(nsError.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
}

#Preview {
    TabAIPersonasView()
}
