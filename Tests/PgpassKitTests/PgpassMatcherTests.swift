import XCTest
@testable import PgpassKit

final class PgpassMatcherTests: XCTestCase {
    private let entries = [
        PgpassEntry(host: "localhost", port: "5432", database: "*", username: "postgres", password: "a"),
        PgpassEntry(host: "staging", port: "5432", database: "orders", username: "svc", password: "b"),
        PgpassEntry(host: "*", port: "5432", database: "*", username: "postgres", password: "c"),
        PgpassEntry(host: "localhost", port: "5432", database: "scratch", username: "postgres", password: "d"),
    ]

    func testFirstMatchWins() {
        let q = ConnectionQuery(host: "localhost", port: "5432", database: "scratch", username: "postgres")
        XCTAssertEqual(PgpassMatcher.firstMatch(in: entries, for: q), 0)
    }

    func testWildcardHostCatchesOthers() {
        let q = ConnectionQuery(host: "elsewhere", port: "5432", database: "x", username: "postgres")
        XCTAssertEqual(PgpassMatcher.firstMatch(in: entries, for: q), 2)
    }

    func testEmptyHostMatchesLocalhost() {
        let q = ConnectionQuery(host: "", port: "5432", database: "x", username: "postgres")
        XCTAssertEqual(PgpassMatcher.firstMatch(in: entries, for: q), 0)
    }

    func testNoMatch() {
        let q = ConnectionQuery(host: "staging", port: "6432", database: "orders", username: "svc")
        XCTAssertNil(PgpassMatcher.firstMatch(in: entries, for: q))
        XCTAssertEqual(PgpassMatcher.fieldResults(entries[1], q), [true, false, true, true])
    }

    func testCoversIsOneWay() {
        XCTAssertTrue(PgpassMatcher.covers(entries[0], entries[3]))
        XCTAssertFalse(PgpassMatcher.covers(entries[3], entries[0]))
    }

    func testShadowing() {
        XCTAssertEqual(PgpassMatcher.shadowing(entries), [nil, nil, nil, 0])
    }
}
