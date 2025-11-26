
import SwiftUI
import CoreData

struct MultiAgentServiceSelector: View {
    @Binding var selectedServices: [APIServiceEntity]
    @Binding var isVisible: Bool
    let availableServices: [APIServiceEntity]
    private let maxSelectedServices = 3
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Select AI Services")
                    .font(.headline)
                
                Spacer()
                
                Button("Close") {
                    isVisible = false
                }
                .buttonStyle(.plain)
            }
            
            Text("Choose up to \(maxSelectedServices) AI services to get responses from different models simultaneously.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(availableServices, id: \.id) { service in
                        ServiceSelectionRow(
                            service: service,
                            isSelected: selectedServices.contains(where: { $0.id == service.id }),
                            selectionCount: selectedServices.filter({ $0.id == service.id }).count,
                            isDisabled: !selectedServices.contains(where: { $0.id == service.id }) && selectedServices.count >= maxSelectedServices
                        ) { isSelected in
                            if isSelected && selectedServices.count < maxSelectedServices {
                                selectedServices.append(service)
                            } else if !isSelected {
                                // Remove the first occurrence of this service
                                if let index = selectedServices.firstIndex(where: { $0.id == service.id }) {
                                    selectedServices.remove(at: index)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            
            HStack {
                Text("\(selectedServices.count)/\(maxSelectedServices) services selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Select Best 3") {
                    // Auto-select top 3 services with valid API keys
                    let validServices = availableServices.filter { service in
                        guard let serviceId = service.id?.uuidString else { return false }
                        do {
                            let token = try TokenManager.getToken(for: serviceId)
                            return token != nil && !token!.isEmpty
                        } catch {
                            return false
                        }
                    }
                    selectedServices = Array(validServices.prefix(maxSelectedServices))
                }
                .disabled(selectedServices.count == maxSelectedServices)
                
                Button("Clear All") {
                    selectedServices.removeAll()
                }
                .disabled(selectedServices.isEmpty)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 8)
    }
}

struct ServiceSelectionRow: View {
    let service: APIServiceEntity
    let isSelected: Bool
    let selectionCount: Int
    let isDisabled: Bool
    let onToggle: (Bool) -> Void
    
    private var serviceDisplayName: String {
        return service.name ?? "Unknown"
    }
    
    private var serviceModelName: String {
        let baseName = service.model ?? "Unknown Model"
        // Show count if selected multiple times
        if selectionCount > 1 {
            return "\(baseName) (×\(selectionCount))"
        }
        return baseName
    }
    
    private var serviceLogoName: String {
        return "logo_\(service.type ?? "unknown")"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                if !isDisabled || isSelected {
                    onToggle(!isSelected)
                }
            }) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : (isDisabled ? .gray : .secondary))
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled && !isSelected)
            
            // Use same AI service logos as in chat
            Image(serviceLogoName)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .foregroundColor(isDisabled && !isSelected ? .gray : .blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(serviceDisplayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDisabled && !isSelected ? .gray : .primary)
                
                Text(serviceModelName)
                    .font(.caption)
                    .foregroundColor(isDisabled && !isSelected ? .gray : .secondary)
            }
            
            Spacer()
            
            // Status indicator
            Circle()
                .fill(hasValidApiKey ? .green : .red)
                .frame(width: 8, height: 8)
                .opacity(isDisabled && !isSelected ? 0.5 : 1.0)
        }
        .padding(8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .opacity(isDisabled && !isSelected ? 0.6 : 1.0)
    }
    
    private var hasValidApiKey: Bool {
        guard let serviceId = service.id?.uuidString else { return false }
        
        do {
            let token = try TokenManager.getToken(for: serviceId)
            return token != nil && !token!.isEmpty
        } catch {
            return false
        }
    }
}

#Preview {
    MultiAgentServiceSelector(
        selectedServices: .constant([]),
        isVisible: .constant(true),
        availableServices: []
    )
    .frame(width: 400, height: 500)
} 
