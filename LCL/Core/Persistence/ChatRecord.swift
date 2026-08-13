import Foundation
import GRDB

/// The `chat` row. Ids are stored as `uuidString` rather than relying on GRDB's default UUID
/// encoding — one less unverified API detail to carry (docs/RESEARCH_LOG.md §11).
struct ChatRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "chat"

    var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
}
