import Foundation

public struct ConnectionQuery: Equatable, Sendable {
    public var host: String
    public var port: String
    public var database: String
    public var username: String

    public init(host: String, port: String, database: String, username: String) {
        self.host = host
        self.port = port
        self.database = database
        self.username = username
    }

    /// libpq matches an empty host against "localhost".
    public var effectiveFields: [String] {
        [host.isEmpty ? "localhost" : host, port, database, username]
    }
}

/// libpq uses the password from the first line whose four fields match.
public enum PgpassMatcher {
    public static func field(_ pattern: String, matches value: String) -> Bool {
        pattern == "*" || pattern == value
    }

    /// Per-field match results: host, port, database, username.
    public static func fieldResults(_ entry: PgpassEntry, _ query: ConnectionQuery) -> [Bool] {
        zip(entry.matchFields, query.effectiveFields).map { field($0, matches: $1) }
    }

    public static func matches(_ entry: PgpassEntry, _ query: ConnectionQuery) -> Bool {
        fieldResults(entry, query).allSatisfy { $0 }
    }

    /// Index of the entry libpq would use, if any.
    public static func firstMatch(in entries: [PgpassEntry], for query: ConnectionQuery) -> Int? {
        entries.firstIndex { matches($0, query) }
    }

    /// True when every connection `b` matches is also matched by `a`.
    public static func covers(_ a: PgpassEntry, _ b: PgpassEntry) -> Bool {
        zip(a.matchFields, b.matchFields).allSatisfy { $0 == "*" || $0 == $1 }
    }

    /// For each entry, the index of the first earlier entry that covers it.
    /// A non-nil value means libpq will never use that entry.
    public static func shadowing(_ entries: [PgpassEntry]) -> [Int?] {
        entries.indices.map { i in
            (0..<i).first { covers(entries[$0], entries[i]) }
        }
    }
}
