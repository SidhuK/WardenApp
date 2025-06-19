import CoreData
import SwiftUI

struct TabAPIServicesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    @State private var isShowingAddOrEditService = false
    @State private var selectedServiceID: NSManagedObjectID?
    @State private var refreshID = UUID()
    @AppStorage("defaultApiService") private var defaultApiServiceID: String?

    private var isSelectedServiceDefault: Bool {
        guard let selectedServiceID = selectedServiceID else { return false }
        return selectedServiceID.uriRepresentation().absoluteString == defaultApiServiceID
    }

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
                            if selectedServiceID != nil {
                                Button(action: onEdit) {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .keyboardShortcut(.defaultAction)

                                Button(action: onDuplicate) {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)

                                if !isSelectedServiceDefault {
                                    Button(action: {
                                        defaultApiServiceID = selectedServiceID?.uriRepresentation().absoluteString
                                    }) {
                                        Label("Set as Default", systemImage: "star")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                }
                                Spacer()
                            }
                            else {
                                Spacer()
                            }
                            Button(action: onAdd) {
                                Label("Add New Service", systemImage: "plus")
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
        .sheet(isPresented: $isShowingAddOrEditService) {
            let selectedApiService = apiServices.first(where: { $0.objectID == selectedServiceID }) ?? nil
            if selectedApiService == nil {
                APIServiceDetailView(viewContext: viewContext, apiService: nil)
            }
            else {
                APIServiceDetailView(viewContext: viewContext, apiService: selectedApiService)
            }
        }
    }

    private var entityListView: some View {
        EntityListView(
            selectedEntityID: $selectedServiceID,
            entities: apiServices,
            detailContent: detailContent,
            onRefresh: refreshList,
            getEntityColor: { _ in nil },
            getEntityName: { $0.name ?? "Untitled Service" },
            getEntityDefault: { $0.objectID.uriRepresentation().absoluteString == defaultApiServiceID },
            getEntityIcon: { "logo_" + ($0.type ?? "") },
            onEdit: {
                if selectedServiceID != nil {
                    isShowingAddOrEditService = true
                }
            },
            onMove: nil
        )
    }

    private func detailContent(service: APIServiceEntity?) -> some View {
        Group {
            if let service = service {
                VStack(alignment: .leading, spacing: 10) {
                    detailRow(label: "Type", value: AppConstants.defaultApiConfigurations[service.type!]?.name ?? "Unknown")
                    detailRow(label: "Model", value: service.model ?? "Not specified")
                    detailRow(label: "Context Size", value: "\(service.contextSize)")
                    detailRow(label: "Auto Chat Naming", value: service.generateChatNames ? "Enabled" : "Disabled")
                    detailRow(label: "Default Assistant", value: service.defaultPersona?.name ?? "None")
                }
                .padding(10)
            }
            else {
                Text("Select an API service to view details")
                    .foregroundColor(.secondary)
                    .font(.callout)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
            }
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    private func refreshList() {
        refreshID = UUID()
    }

    private func onAdd() {
        selectedServiceID = nil
        isShowingAddOrEditService = true
    }

    private func onDuplicate() {
        if let selectedService = apiServices.first(where: { $0.objectID == selectedServiceID }) {
            let newService = selectedService.copy() as! APIServiceEntity
            newService.name = (selectedService.name ?? "") + " Copy"
            newService.addedDate = Date()

            // Generate new UUID and copy the token
            let newServiceID = UUID()
            newService.id = newServiceID

            if let oldServiceIDString = selectedService.id?.uuidString {
                do {
                    if let token = try TokenManager.getToken(for: oldServiceIDString) {
                        try TokenManager.setToken(token, for: newServiceID.uuidString)
                    }
                }
                catch {
                    print("Error copying API token: \(error)")
                }
            }

            do {
                try viewContext.save()
                refreshList()
            }
            catch {
                print("Error duplicating service: \(error)")
            }
        }
    }

    private func onEdit() {
        isShowingAddOrEditService = true
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
struct InlineTabAPIServicesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    @State private var isShowingAddOrEditService = false
    @State private var selectedServiceID: NSManagedObjectID?
    @State private var refreshID = UUID()
    @AppStorage("defaultApiService") private var defaultApiServiceID: String?

    // Colors matching the chat app theme
    private let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    private var cardBackgroundColor: Color {
        Color(NSColor.controlBackgroundColor)
    }

    private var isSelectedServiceDefault: Bool {
        guard let selectedServiceID = selectedServiceID else { return false }
        return selectedServiceID.uriRepresentation().absoluteString == defaultApiServiceID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "network", title: "API Services")
            
            settingGroup {
                VStack(spacing: 16) {
                    entityListView
                        .id(refreshID)
                        .frame(minHeight: 260)

                    Divider()

                    HStack(spacing: 20) {
                        if selectedServiceID != nil {
                            Button(action: onEdit) {
                                Label("Edit", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .keyboardShortcut(.defaultAction)

                            Button(action: onDuplicate) {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)

                            if !isSelectedServiceDefault {
                                Button(action: {
                                    defaultApiServiceID = selectedServiceID?.uriRepresentation().absoluteString
                                }) {
                                    Label("Set as Default", systemImage: "star")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                            }
                            Spacer()
                        }
                        else {
                            Spacer()
                        }
                        Button(action: onAdd) {
                            Label("Add New Service", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAddOrEditService) {
            let selectedApiService = apiServices.first(where: { $0.objectID == selectedServiceID }) ?? nil
            if selectedApiService == nil {
                APIServiceDetailView(viewContext: viewContext, apiService: nil)
            }
            else {
                APIServiceDetailView(viewContext: viewContext, apiService: selectedApiService)
            }
        }
    }

    private var entityListView: some View {
        EntityListView(
            selectedEntityID: $selectedServiceID,
            entities: apiServices,
            detailContent: detailContent,
            onRefresh: refreshList,
            getEntityColor: { _ in nil },
            getEntityName: { $0.name ?? "Untitled Service" },
            getEntityDefault: { $0.objectID.uriRepresentation().absoluteString == defaultApiServiceID },
            getEntityIcon: { "logo_" + ($0.type ?? "") },
            onEdit: {
                if selectedServiceID != nil {
                    isShowingAddOrEditService = true
                }
            },
            onMove: nil
        )
    }

    private func detailContent(service: APIServiceEntity?) -> some View {
        Group {
            if let service = service {
                VStack(alignment: .leading, spacing: 10) {
                    detailRow(label: "Type", value: AppConstants.defaultApiConfigurations[service.type!]?.name ?? "Unknown")
                    detailRow(label: "Model", value: service.model ?? "Not specified")
                    detailRow(label: "Context Size", value: "\(service.contextSize)")
                    detailRow(label: "Auto Chat Naming", value: service.generateChatNames ? "Enabled" : "Disabled")
                    detailRow(label: "Default Assistant", value: service.defaultPersona?.name ?? "None")
                }
                .padding(10)
            }
            else {
                Text("Select an API service to view details")
                    .foregroundColor(.secondary)
                    .font(.callout)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
            }
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    private func refreshList() {
        refreshID = UUID()
    }

    private func onAdd() {
        selectedServiceID = nil
        isShowingAddOrEditService = true
    }

    private func onDuplicate() {
        if let selectedService = apiServices.first(where: { $0.objectID == selectedServiceID }) {
            let newService = selectedService.copy() as! APIServiceEntity
            newService.name = (selectedService.name ?? "") + " Copy"
            newService.addedDate = Date()

            // Generate new UUID and copy the token
            let newServiceID = UUID()
            newService.id = newServiceID

            if let oldServiceIDString = selectedService.id?.uuidString {
                do {
                    if let token = try TokenManager.getToken(for: oldServiceIDString) {
                        try TokenManager.setToken(token, for: newServiceID.uuidString)
                    }
                }
                catch {
                    print("Error copying API token: \(error)")
                }
            }

            do {
                try viewContext.save()
                refreshList()
            }
            catch {
                print("Error duplicating service: \(error)")
            }
        }
    }

    private func onEdit() {
        isShowingAddOrEditService = true
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

struct APIServiceRowView: View {
    let service: APIServiceEntity

    var body: some View {
        VStack(alignment: .leading) {
            Text(service.name ?? "Untitled Service")
                .font(.headline)
            Text(service.type ?? "Unknown type")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
