import Foundation

/// Reads and writes the .pgpass format the way libpq does:
/// - lines starting with '#' are comments
/// - fields are separated by ':'; a backslash escapes the next character
/// - everything after the fourth unescaped ':' is the password
public enum PgpassParser {
    public static func parse(_ text: String) -> [PgpassLine] {
        var rawLines = text.components(separatedBy: "\n")
        if rawLines.last == "" { rawLines.removeLast() }
        return rawLines.map(parseLine)
    }

    public static func parseLine(_ rawLine: String) -> PgpassLine {
        var line = rawLine
        if line.hasSuffix("\r") { line.removeLast() }

        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return PgpassLine(kind: .blank, raw: rawLine)
        }
        if line.hasPrefix("#") {
            return PgpassLine(kind: .comment(line), raw: rawLine)
        }
        guard let entry = parseEntry(line) else {
            return PgpassLine(kind: .unparsed(line), raw: rawLine)
        }
        return PgpassLine(kind: .entry(entry), raw: rawLine)
    }

    static func parseEntry(_ line: String) -> PgpassEntry? {
        var fields: [String] = []
        var current = ""
        var escaping = false
        var index = line.startIndex

        while index < line.endIndex, fields.count < 4 {
            let ch = line[index]
            if escaping {
                current.append(ch)
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else if ch == ":" {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            index = line.index(after: index)
        }
        guard fields.count == 4 else { return nil }

        let password = unescape(line[index...])
        return PgpassEntry(host: fields[0], port: fields[1], database: fields[2], username: fields[3], password: password)
    }

    static func unescape<S: StringProtocol>(_ text: S) -> String {
        var out = ""
        var escaping = false
        for ch in text {
            if escaping {
                out.append(ch)
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else {
                out.append(ch)
            }
        }
        return out
    }

    public static func escape(_ value: String) -> String {
        var out = ""
        for ch in value {
            if ch == "\\" || ch == ":" { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// The line for an entry, with every field escaped.
    public static func format(_ entry: PgpassEntry) -> String {
        [entry.host, entry.port, entry.database, entry.username, entry.password]
            .map(escape)
            .joined(separator: ":")
    }

    /// Like `format`, but with the password replaced by bullets.
    public static func formatMasked(_ entry: PgpassEntry, bullets: Int = 8) -> String {
        entry.matchFields.map(escape).joined(separator: ":") + ":" + String(repeating: "•", count: bullets)
    }

    public static func render(_ line: PgpassLine) -> String {
        if let raw = line.raw { return raw }
        switch line.kind {
        case .entry(let entry): return format(entry)
        case .comment(let text): return text
        case .blank: return ""
        case .unparsed(let text): return text
        }
    }

    public static func serialize(_ lines: [PgpassLine]) -> String {
        guard !lines.isEmpty else { return "" }
        return lines.map(render).joined(separator: "\n") + "\n"
    }
}
