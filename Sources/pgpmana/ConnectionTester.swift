import Foundation
import PgpassKit

/// psql and pg_isready, if they're installed somewhere we can find them.
///
/// Apps opened from Finder don't get your shell's PATH, so this also looks in
/// the usual install locations: Homebrew (including the keg-only libpq and
/// postgresql@N formulas), Postgres.app, and the EDB installer.
struct PostgresTools: Sendable {
    var psql: URL?
    var pgIsReady: URL?

    var isEmpty: Bool { psql == nil && pgIsReady == nil }

    static func find() -> PostgresTools {
        let fm = FileManager.default
        var dirs: [String] = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        dirs += [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/homebrew/opt/libpq/bin",
            "/usr/local/opt/libpq/bin",
            "/Applications/Postgres.app/Contents/Versions/latest/bin",
        ]
        // Versioned installs, newest name first.
        for parent in ["/opt/homebrew/opt", "/usr/local/opt"] {
            let names = (try? fm.contentsOfDirectory(atPath: parent)) ?? []
            dirs += names.filter { $0.hasPrefix("postgresql") }.sorted(by: >).map { "\(parent)/\($0)/bin" }
        }
        for parent in ["/Library/PostgreSQL", "/Applications/Postgres.app/Contents/Versions"] {
            let names = (try? fm.contentsOfDirectory(atPath: parent)) ?? []
            dirs += names.sorted(by: >).map { "\(parent)/\($0)/bin" }
        }

        func first(_ name: String) -> URL? {
            for dir in dirs {
                let path = (dir as NSString).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
            }
            return nil
        }
        return PostgresTools(psql: first("psql"), pgIsReady: first("pg_isready"))
    }
}

struct ConnectionTarget: Sendable {
    var host: String
    var port: String
    var database: String
    var username: String
    var password: String
}

struct ConnectionOutcome: Sendable {
    var ok: Bool
    var title: String
    var detail: String
    /// The command that ran, without the password.
    var command: String
}

enum ConnectionTester {
    /// With psql, logs in for real using only this entry's password, so a
    /// wrong or stale password shows up. With only pg_isready, checks that the
    /// server accepts connections; pg_isready can't check a password.
    static func test(_ target: ConnectionTarget, tools: PostgresTools) async -> ConnectionOutcome {
        if let psql = tools.psql {
            return await testWithPsql(psql, target)
        }
        if let pgIsReady = tools.pgIsReady {
            return await testWithPgIsReady(pgIsReady, target)
        }
        return ConnectionOutcome(ok: false, title: "psql isn't installed",
                                 detail: "Install it with `brew install libpq`, then try again.", command: "")
    }

    private static func testWithPsql(_ psql: URL, _ t: ConnectionTarget) async -> ConnectionOutcome {
        // A one-line password file holding just this entry, so psql can't pick
        // up a different line from ~/.pgpass and the escaping gets tested too.
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pgpmana-test-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            return ConnectionOutcome(ok: false, title: "Couldn't start the test", detail: error.localizedDescription, command: "")
        }
        defer { try? fm.removeItem(at: dir) }

        let passfile = dir.appendingPathComponent("pgpass")
        let entry = PgpassEntry(host: t.host, port: t.port, database: t.database, username: t.username, password: t.password)
        do {
            try PgpassFile.write([PgpassLine(kind: .entry(entry))], to: passfile, backupSuffix: nil)
        } catch {
            return ConnectionOutcome(ok: false, title: "Couldn't start the test", detail: error.localizedDescription, command: "")
        }

        var env = ProcessInfo.processInfo.environment
        env["PGPASSFILE"] = passfile.path
        env["PGCONNECT_TIMEOUT"] = "5"
        env.removeValue(forKey: "PGPASSWORD") // it would win over the file

        let args = ["-X", "-w", "-A", "-t",
                    "-h", t.host, "-p", t.port, "-U", t.username, "-d", t.database,
                    "-c", "select version()"]
        let command = "psql " + args.map(shellQuote).joined(separator: " ")
        let result = await run(psql, args, env: env, timeout: 15)

        if result.timedOut {
            return ConnectionOutcome(ok: false, title: "Timed out", detail: "psql didn't finish within 15 seconds.", command: command)
        }
        if result.status == 0 {
            let version = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
            return ConnectionOutcome(
                ok: true,
                title: "Connected",
                detail: "Logged in to \(t.database) on \(t.host):\(t.port) as \(t.username) with this entry's password."
                    + (version.isEmpty ? "" : "\n\n" + version),
                command: command
            )
        }
        var message = result.err.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.hasPrefix("psql: error: ") { message.removeFirst("psql: error: ".count) }
        return ConnectionOutcome(ok: false, title: "Couldn't connect",
                                 detail: message.isEmpty ? "psql exited with status \(result.status)." : message,
                                 command: command)
    }

    private static func testWithPgIsReady(_ tool: URL, _ t: ConnectionTarget) async -> ConnectionOutcome {
        let args = ["-h", t.host, "-p", t.port, "-U", t.username, "-d", t.database, "-t", "5"]
        let command = "pg_isready " + args.map(shellQuote).joined(separator: " ")
        let result = await run(tool, args, env: ProcessInfo.processInfo.environment, timeout: 15)
        let note = "pg_isready can't check passwords, so this only tells you whether the server is up. Install psql (`brew install libpq`) to test the login too."
        let output = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
        switch result.status {
        case 0:
            return ConnectionOutcome(ok: true, title: "Server is accepting connections", detail: note, command: command)
        case 1:
            return ConnectionOutcome(ok: false, title: "Server is rejecting connections", detail: output + "\n\n" + note, command: command)
        case 2:
            return ConnectionOutcome(ok: false, title: "No response from the server", detail: output + "\n\n" + note, command: command)
        default:
            let detail = result.timedOut ? "pg_isready didn't finish within 15 seconds." : (output.isEmpty ? result.err : output)
            return ConnectionOutcome(ok: false, title: "Couldn't run the check", detail: detail, command: command)
        }
    }

    private struct RunResult: Sendable {
        var status: Int32
        var out: String
        var err: String
        var timedOut: Bool
    }

    private static func run(_ executable: URL, _ args: [String], env: [String: String], timeout: TimeInterval) async -> RunResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = args
                process.environment = env
                process.standardInput = FileHandle.nullDevice
                let outPipe = Pipe(), errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: RunResult(status: -1, out: "", err: error.localizedDescription, timedOut: false))
                    return
                }
                let timedOut = TimeoutFlag()
                let killer = DispatchWorkItem {
                    if process.isRunning {
                        timedOut.set()
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let out = outPipe.fileHandleForReading.readDataToEndOfFile()
                let err = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                killer.cancel()
                continuation.resume(returning: RunResult(
                    status: process.terminationStatus,
                    out: String(decoding: out, as: UTF8.self),
                    err: String(decoding: err, as: UTF8.self),
                    timedOut: timedOut.value
                ))
            }
        }
    }

    private static func shellQuote(_ s: String) -> String {
        let safe = s.allSatisfy { $0.isLetter || $0.isNumber || "-_.:/@".contains($0) }
        return safe && !s.isEmpty ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// A flag set from the timeout queue and read on the worker queue.
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
