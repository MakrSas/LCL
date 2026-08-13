import Foundation
import GRDB

enum AppDatabaseError: LocalizedError {
    case directoryUnavailable

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable:
            return "Could not locate the app's Application Support directory."
        }
    }
}

/// Owns the single on-disk database for the app. `ChatStore` is the only thing that opens
/// one; nothing else touches GRDB directly (docs/ARCHITECTURE.md §"Persistence").
enum AppDatabase {

    static func open() throws -> DatabaseQueue {
        let directory = try applicationSupportDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("lcl.sqlite")
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let queue = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(queue)
        try protectAndExcludeFromBackup(at: url)
        return queue
    }

    /// For tests: same schema, same pragmas (`ON DELETE CASCADE` needs `foreign_keys = ON`
    /// per connection, same as `open()`), no file on disk.
    static func openInMemory() throws -> DatabaseQueue {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(configuration: config)
        try migrator.migrate(queue)
        return queue
    }

    private static func applicationSupportDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppDatabaseError.directoryUnavailable
        }
        return base.appendingPathComponent("LCL", isDirectory: true)
    }

    /// Chat history is exactly the data Data Protection exists for, and it has no reason to
    /// leave the device via iCloud backup — restoring to a new phone should not silently
    /// resurrect old conversations into a fresh install (docs/PHASE_1_PLAN.md Step 2).
    private static func protectAndExcludeFromBackup(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    /// Raw SQL rather than GRDB's table-builder DSL for the FTS5 half of this migration:
    /// external-content FTS5 plus its sync triggers is a SQLite-documented pattern with an
    /// exact, load-bearing shape (docs/RESEARCH_LOG.md §11 records the cost of trusting an
    /// API detail instead of writing the unambiguous form). Plain SQL is that unambiguous
    /// form and is stable across GRDB versions.
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_chats_and_messages") { db in
            try db.execute(sql: """
                CREATE TABLE chat (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL
                );

                CREATE TABLE message (
                    id TEXT PRIMARY KEY NOT NULL,
                    chatID TEXT NOT NULL REFERENCES chat(id) ON DELETE CASCADE,
                    role TEXT NOT NULL,
                    text TEXT NOT NULL DEFAULT '',
                    thinking TEXT NOT NULL DEFAULT '',
                    isStreaming INTEGER NOT NULL DEFAULT 0,
                    promptTokens INTEGER,
                    completionTokens INTEGER,
                    tokensPerSecond REAL,
                    createdAt DATETIME NOT NULL
                );
                CREATE INDEX message_on_chatID ON message(chatID);

                CREATE VIRTUAL TABLE message_fts USING fts5(
                    text,
                    content='message',
                    content_rowid='rowid'
                );

                CREATE TRIGGER message_ai AFTER INSERT ON message BEGIN
                    INSERT INTO message_fts(rowid, text) VALUES (new.rowid, new.text);
                END;

                CREATE TRIGGER message_ad AFTER DELETE ON message BEGIN
                    INSERT INTO message_fts(message_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
                END;

                CREATE TRIGGER message_au AFTER UPDATE ON message BEGIN
                    INSERT INTO message_fts(message_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
                    INSERT INTO message_fts(rowid, text) VALUES (new.rowid, new.text);
                END;
                """)
        }

        return migrator
    }
}
