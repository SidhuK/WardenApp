import Foundation

struct MCPServerConfig: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var transportType: TransportType
    var command: String?
    var arguments: [String] = []
    var environment: [String: String] = [:]
    var url: URL?
    var enabled: Bool = true

    enum TransportType: String, Codable, CaseIterable {
        case stdio
        case sse
    }
}
