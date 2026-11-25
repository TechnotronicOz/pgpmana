import XCTest
@testable import PgpassKit

final class ConnectionURLTests: XCTestCase {
    func testFullURL() throws {
        let e = try ConnectionURL.parse("postgres://svc_orders:s3cret@staging-db.example.internal:6432/orders?sslmode=require")
        XCTAssertEqual(e, PgpassEntry(host: "staging-db.example.internal", port: "6432", database: "orders", username: "svc_orders", password: "s3cret"))
    }

    func testDefaultsFollowLibpq() throws {
        let e = try ConnectionURL.parse("postgresql://matt:pw@/")
        XCTAssertEqual(e.host, "localhost")
        XCTAssertEqual(e.port, "5432")
        XCTAssertEqual(e.database, "matt")
    }

    func testPercentEncodingIsDecoded() throws {
        let e = try ConnectionURL.parse("postgres://app%40corp:p%3Aw%2Fd@db:5432/app")
        XCTAssertEqual(e.username, "app@corp")
        XCTAssertEqual(e.password, "p:w/d")
        // And it round-trips through the file format with escapes.
        XCTAssertEqual(PgpassParser.format(e), #"db:5432:app:app@corp:p\:w/d"#)
    }

    func testQueryParametersOverride() throws {
        let e = try ConnectionURL.parse("postgres://u:pw@ignored:1/ignored?host=real&port=5433&dbname=prod")
        XCTAssertEqual(e.host, "real")
        XCTAssertEqual(e.port, "5433")
        XCTAssertEqual(e.database, "prod")
    }

    func testIPv6Host() throws {
        let e = try ConnectionURL.parse("postgres://u:pw@[::1]:5544/db")
        XCTAssertEqual(e.host, "::1")
        XCTAssertEqual(e.port, "5544")
        XCTAssertEqual(PgpassParser.format(e), #"\:\:1:5544:db:u:pw"#)
    }

    func testErrors() {
        XCTAssertThrowsError(try ConnectionURL.parse("localhost:5432")) { XCTAssertEqual($0 as? ConnectionURLError, .notAURL) }
        XCTAssertThrowsError(try ConnectionURL.parse("mysql://u:p@h/db")) { XCTAssertEqual($0 as? ConnectionURLError, .unsupportedScheme("mysql")) }
        XCTAssertThrowsError(try ConnectionURL.parse("postgres://u:p@a:1,b:2/db")) { XCTAssertEqual($0 as? ConnectionURLError, .multipleHosts) }
        XCTAssertThrowsError(try ConnectionURL.parse("postgres://h/db")) { XCTAssertEqual($0 as? ConnectionURLError, .missingUser) }
        XCTAssertThrowsError(try ConnectionURL.parse("postgres://u@h/db")) { XCTAssertEqual($0 as? ConnectionURLError, .missingPassword) }
    }

    func testLooksLikeURL() {
        XCTAssertTrue(ConnectionURL.looksLikeURL("  postgresql://x"))
        XCTAssertFalse(ConnectionURL.looksLikeURL("https://example.com"))
    }
}
