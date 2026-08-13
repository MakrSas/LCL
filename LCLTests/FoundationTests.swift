import XCTest
@testable import LCL

/// Step 0 gate (docs/PHASE_1_PLAN.md): the dependency graph links on a real iOS runtime.
/// The GRDB/FTS5 half of this used to live here as a standalone probe; Step 2 landed the
/// real schema, so that coverage now lives in `ChatStoreTests` against the actual tables
/// instead of a throwaway one.
final class FoundationTests: XCTestCase {

    func testMLXGraphLinks() {
        XCTAssertTrue(InferenceLinkProbe.linked)
    }
}
