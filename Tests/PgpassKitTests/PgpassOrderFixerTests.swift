import XCTest
@testable import PgpassKit

final class PgpassOrderFixerTests: XCTestCase {
    private func entries(_ lines: [PgpassLine]) -> [String] {
        lines.compactMap { $0.entry.map { $0.matchFields.joined(separator: ":") } }
    }

    func testMovesHiddenEntryAboveTheOneHidingIt() {
        let lines = PgpassParser.parse("""
        # local
        localhost:5432:*:postgres:a
        localhost:5433:app:app:b
        localhost:5432:scratch:postgres:c
        """)
        let fix = PgpassOrderFixer.fix(lines)
        XCTAssertEqual(fix.moves.count, 1)
        XCTAssertEqual(entries(fix.lines), [
            "localhost:5432:scratch:postgres",
            "localhost:5432:*:postgres",
            "localhost:5433:app:app",
        ])
        // The comment stays first.
        XCTAssertEqual(fix.lines.first?.kind, .comment("# local"))
        XCTAssertTrue(PgpassMatcher.shadowing(fix.lines.compactMap(\.entry)).allSatisfy { $0 == nil })
    }

    func testChainOfWildcardsEndsWithNothingHidden() {
        let lines = PgpassParser.parse("""
        *:*:*:*:any
        *:5432:*:postgres:p
        localhost:5432:*:postgres:l
        localhost:5432:app:postgres:x
        """)
        let fix = PgpassOrderFixer.fix(lines)
        XCTAssertTrue(fix.duplicates.isEmpty)
        XCTAssertTrue(PgpassMatcher.shadowing(fix.lines.compactMap(\.entry)).allSatisfy { $0 == nil })
        XCTAssertEqual(entries(fix.lines).last, "*:*:*:*")
    }

    func testDuplicatesAreReportedNotMoved() {
        let lines = PgpassParser.parse("""
        localhost:5432:app:app:first
        localhost:5432:app:app:second
        """)
        let fix = PgpassOrderFixer.fix(lines)
        XCTAssertFalse(fix.changesOrder)
        XCTAssertEqual(fix.duplicates.count, 1)
        XCTAssertEqual(fix.duplicates.first?.lineID, lines[1].id)
        XCTAssertEqual(fix.duplicates.first?.originalID, lines[0].id)
    }

    func testAlreadyCorrectFileIsUnchanged() {
        let lines = PgpassParser.parse("""
        localhost:5432:app:app:a
        *:5432:*:postgres:b
        """)
        let fix = PgpassOrderFixer.fix(lines)
        XCTAssertFalse(fix.changesOrder)
        XCTAssertEqual(fix.lines, lines)
    }
}
