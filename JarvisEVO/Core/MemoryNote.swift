import Foundation

struct MemoryNote: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var content: String
    var createdAt: Date = Date()
}
