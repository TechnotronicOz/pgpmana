import XCTest
@testable import PgpassKit

final class PgpassParserTests: XCTestCase {
    func testParsesPlainEntry() {
        let line = PgpassParser.parseLine("localhost:5432:app:alice:secret")
        XCTAssertEqual(line.entry, PgpassEntry(host: "localhost", port: "5432", database: "app", username: "alice", password: "secret"))
    }

    func testUnescapesColonsAndBackslashes() {
        let line = PgpassParser.parseLine(#"db\:host:5432:*:bob:pa\:ss\\word"#)
        XCTAssertEqual(line.entry?.host, "db:host")
        XCTAssertEqual(line.entry?.database, "*")
        XCTAssertEqual(line.entry?.password, #"pa:ss\word"#)
    }

    func testPasswordKeepsUnescapedColons() {
        // libpq treats everything after the fourth separator as the password.
        let line = PgpassParser.parseLine("h:1:d:u:a:b")
        XCTAssertEqual(line.entry?.password, "a:b")
    }

    func testCommentsBlanksAndUnparsedLines() {
        let lines = PgpassParser.parse("# staging\n\nnot-an-entry\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].kind, .comment("# staging"))
        XCTAssertEqual(lines[1].kind, .blank)
        XCTAssertEqual(lines[2].kind, .unparsed("not-an-entry"))
    }

    func testStripsCarriageReturnButKeepsRaw() {
        let line = PgpassParser.parseLine("h:1:d:u:pw\r")
        XCTAssertEqual(line.entry?.password, "pw")
        XCTAssertEqual(PgpassParser.render(line), "h:1:d:u:pw\r")
    }

    func testUntouchedFileRoundTripsExactly() {
        let text = "# local\nlocalhost:5432:*:postgres:x\n\njunk line\nh:1:d:u:p\\x\n"
        XCTAssertEqual(PgpassParser.serialize(PgpassParser.parse(text)), text)
    }

    func testEditedLineIsReEscaped() {
        var line = PgpassParser.parseLine("h:1:d:u:old")
        line.setKind(.entry(PgpassEntry(host: "h", port: "1", database: "d", username: "u", password: #"n:e\w"#)))
        XCTAssertEqual(PgpassParser.render(line), #"h:1:d:u:n\:e\\w"#)
    }

    func testFormatThenParseIsLossless() {
        let entry = PgpassEntry(host: "a:b", port: "5432", database: #"c\d"#, username: "u", password: "::\\")
        XCTAssertEqual(PgpassParser.parseLine(PgpassParser.format(entry)).entry, entry)
    }

    func testMaskedFormatHidesPassword() {
        let entry = PgpassEntry(host: "h", port: "1", database: "d", username: "u", password: "secret")
        XCTAssertEqual(PgpassParser.formatMasked(entry, bullets: 3), "h:1:d:u:•••")
    }
}
