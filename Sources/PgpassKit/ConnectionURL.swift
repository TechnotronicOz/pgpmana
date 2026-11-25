import Foundation

public enum ConnectionURLError: LocalizedError, Equatable {
    case notAURL
    case unsupportedScheme(String)
    case multipleHosts
    case missingUser
    case missingPassword

    public var errorDescription: String? {
        switch self {
        case .notAURL:
            return "That isn't a connection URL. It should start with postgres:// or postgresql://."
        case .unsupportedScheme(let scheme):
            return "\(scheme):// isn't a PostgreSQL URL. Use postgres:// or postgresql://."
        case .multipleHosts:
            return "URLs with more than one host aren't supported. Add one entry per host."
        case .missingUser:
            return "The URL has no user name."
        case .missingPassword:
            return "The URL has no password, so there's nothing to save."
        }
    }
}

/// Parses libpq connection URLs such as
/// `postgres://user:password@host:5432/database?sslmode=require`.
public enum ConnectionURL {
    public static func looksLikeURL(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.hasPrefix("postgres://") || t.hasPrefix("postgresql://")
    }

    /// Fills in libpq's defaults for parts the URL leaves out: host
    /// `localhost`, port `5432`, and a database named after the user.
    /// Query parameters `host`, `port`, `user`, `password` and `dbname`
    /// override the matching parts of the URL, as they do in libpq.
    public static func parse(_ text: String) throws -> PgpassEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schemeEnd = trimmed.range(of: "://") else { throw ConnectionURLError.notAURL }
        let scheme = trimmed[..<schemeEnd.lowerBound].lowercased()
        guard scheme == "postgres" || scheme == "postgresql" else {
            throw ConnectionURLError.unsupportedScheme(scheme)
        }

        let rest = trimmed[schemeEnd.upperBound...]
        let authorityEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" }) ?? rest.endIndex
        let authority = rest[..<authorityEnd]
        var tail = rest[authorityEnd...]

        // user:password@host:port
        var userInfo: Substring = ""
        var hostPort: Substring = authority
        if let at = authority.lastIndex(of: "@") {
            userInfo = authority[..<at]
            hostPort = authority[authority.index(after: at)...]
        }
        if hostPort.contains(",") { throw ConnectionURLError.multipleHosts }

        var user = ""
        var password: String?
        if !userInfo.isEmpty {
            if let colon = userInfo.firstIndex(of: ":") {
                user = decode(userInfo[..<colon])
                password = decode(userInfo[userInfo.index(after: colon)...])
            } else {
                user = decode(userInfo)
            }
        }

        var host = ""
        var port = ""
        if hostPort.hasPrefix("["), let close = hostPort.firstIndex(of: "]") {
            // IPv6 literal: [::1]:5432
            host = String(hostPort[hostPort.index(after: hostPort.startIndex)..<close])
            let after = hostPort[hostPort.index(after: close)...]
            if after.hasPrefix(":") { port = String(after.dropFirst()) }
        } else if let colon = hostPort.lastIndex(of: ":") {
            host = decode(hostPort[..<colon])
            port = String(hostPort[hostPort.index(after: colon)...])
        } else {
            host = decode(hostPort)
        }

        var database = ""
        if tail.hasPrefix("/") {
            let queryStart = tail.firstIndex(of: "?") ?? tail.endIndex
            database = decode(tail[tail.index(after: tail.startIndex)..<queryStart])
            tail = tail[queryStart...]
        }

        if tail.hasPrefix("?") {
            for pair in tail.dropFirst().split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                guard kv.count == 2 else { continue }
                let value = decode(kv[1])
                switch decode(kv[0]) {
                case "host": host = value
                case "port": port = value
                case "user": user = value
                case "password": password = value
                case "dbname": database = value
                default: break
                }
            }
        }

        if host.contains(",") || port.contains(",") { throw ConnectionURLError.multipleHosts }
        guard !user.isEmpty else { throw ConnectionURLError.missingUser }
        guard let password, !password.isEmpty else { throw ConnectionURLError.missingPassword }

        return PgpassEntry(
            host: host.isEmpty ? "localhost" : host,
            port: port.isEmpty ? "5432" : port,
            database: database.isEmpty ? user : database,
            username: user,
            password: password
        )
    }

    static func decode<S: StringProtocol>(_ text: S) -> String {
        String(text).removingPercentEncoding ?? String(text)
    }
}
