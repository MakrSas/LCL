import Foundation
import GRDB

/// Step 0 probe: proves GRDB links **and runs** on iOS, including FTS5.
///
/// FTS5 is the whole reason we are not on SwiftData (docs/DEPENDENCIES.md), so verifying
/// it is actually compiled into the system SQLite on device is worth doing before any
/// schema work depends on it. This is a temporary scaffold — it is deleted in Step 2 when
/// the real `Database` stack lands.
enum DatabaseProbe {

    /// Round-trips a value through an in-memory database.
    static func roundTrip() throws -> Int? {
        let queue = try DatabaseQueue()
        return try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT 1")
        }
    }

    /// Creates an FTS5 table and confirms a BM25-ranked match comes back.
    ///
    /// If this throws, `docs/CONTEXT_ENGINE.md` §4 needs rethinking — so we want to know
    /// on the very first CI run rather than in Phase 2.
    static func fts5IsAvailable() throws -> Bool {
        let queue = try DatabaseQueue()
        return try queue.write { db in
            try db.create(virtualTable: "probe", using: FTS5()) { table in
                table.column("content")
            }
            try db.execute(
                sql: "INSERT INTO probe(content) VALUES (?)",
                arguments: ["the model may forget but LCL must not"]
            )
            let hits = try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM probe WHERE probe MATCH ?",
                arguments: ["forget"]
            )
            return hits == 1
        }
    }
}
