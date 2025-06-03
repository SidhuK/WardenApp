
import Foundation

struct APIServiceConfig: APIServiceConfiguration, Codable {
    var name: String
    var apiUrl: URL
    var apiKey: String
    var model: String
}
