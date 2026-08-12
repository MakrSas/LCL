import XCTest
@testable import LCL

/// Step 0 gate (docs/PHASE_1_PLAN.md): the dependency graph links and the two facts the
/// architecture rests on are true on a real iOS runtime.
final class FoundationTests: XCTestCase {

    func testGRDBRoundTrips() throws {
        XCTAssertEqual(try DatabaseProbe.roundTrip(), 1)
    }

    /// FTS5 is why we chose GRDB over SwiftData. If system SQLite on iOS lacks it, the
    /// ContextEngine retrieval design changes — so this is a load-bearing assertion, not a
    /// smoke test.
    func testFTS5IsAvailableOnIOS() throws {
        XCTAssertTrue(
            try DatabaseProbe.fts5IsAvailable(),
            "FTS5 unavailable — revisit docs/CONTEXT_ENGINE.md §4 and docs/DEPENDENCIES.md"
        )
    }

    func testMLXGraphLinks() {
        XCTAssertTrue(InferenceLinkProbe.linked)
    }
}
