import Foundation

/// One connection entry: hostname:port:database:username:password.
/// Values are stored unescaped. A field that is exactly "*" is a wildcard
/// (password excluded).
public struct PgpassEntry: Equatable, Hashable, Sendable {
    public var host: String
    public var port: String
    public var database: String
    public var username: String
    public var password: String

    public init(host: String = "", port: String = "", database: String = "", username: String = "", password: String = "") {
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.password = password
    }

    /// The four fields libpq matches against, in file order.
    public var matchFields: [String] { [host, port, database, username] }

    public var usesWildcard: Bool { matchFields.contains("*") }
}

public enum PgpassLineKind: Equatable, Hashable, Sendable {
    case entry(PgpassEntry)
    /// A line starting with '#', kept as written.
    case comment(String)
    case blank
    /// A line libpq can't use (fewer than four separators). Kept as written.
    case unparsed(String)
}

/// One physical line of the file. `raw` holds the original text for lines
/// read from disk and is cleared when the line is edited, so untouched lines
/// are written back byte for byte.
public struct PgpassLine: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public private(set) var kind: PgpassLineKind
    public private(set) var raw: String?

    public init(id: UUID = UUID(), kind: PgpassLineKind, raw: String? = nil) {
        self.id = id
        self.kind = kind
        self.raw = raw
    }

    public mutating func setKind(_ newKind: PgpassLineKind) {
        guard newKind != kind else { return }
        kind = newKind
        raw = nil
    }

    public var entry: PgpassEntry? {
        if case .entry(let entry) = kind { return entry }
        return nil
    }
}
