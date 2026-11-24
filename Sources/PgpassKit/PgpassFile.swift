import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum PgpassFileError: LocalizedError {
    case createFailed(path: String, reason: String)
    case writeFailed(path: String, reason: String)
    case renameFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .createFailed(let path, let reason): return "Couldn't create \(path): \(reason)"
        case .writeFailed(let path, let reason): return "Couldn't write \(path): \(reason)"
        case .renameFailed(let path, let reason): return "Couldn't replace \(path): \(reason)"
        }
    }
}

// File-scope wrappers so the C functions don't collide with method names.
private func posixOpenExclusive(_ path: String) -> Int32 {
    open(path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
}
private func posixWrite(_ fd: Int32, _ ptr: UnsafeRawPointer, _ count: Int) -> Int {
    write(fd, ptr, count)
}
private func posixRename(_ from: String, _ to: String) -> Int32 {
    rename(from, to)
}
private func lastErrorText() -> String {
    String(cString: strerror(errno))
}

public enum PgpassFile {
    /// $PGPASSFILE if set, else ~/.pgpass.
    public static func defaultLocation(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["PGPASSFILE"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pgpass")
    }

    public static func posixMode(at url: URL) -> Int? {
        let path = url.resolvingSymlinksInPath().path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mode = attrs[.posixPermissions] as? NSNumber else { return nil }
        return mode.intValue & 0o7777
    }

    public static func modificationDate(at url: URL) -> Date? {
        let path = url.resolvingSymlinksInPath().path
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// libpq ignores the file on Unix if group or others have any access.
    public static func isTooOpen(_ mode: Int) -> Bool {
        mode & 0o077 != 0
    }

    public static func formatMode(_ mode: Int) -> String {
        let octal = String(mode, radix: 8)
        return String(repeating: "0", count: max(0, 4 - octal.count)) + octal
    }

    /// Returns no lines when the file doesn't exist yet.
    public static func read(at url: URL) throws -> [PgpassLine] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return PgpassParser.parse(String(decoding: data, as: UTF8.self))
    }

    /// Writes atomically with mode 0600: a new temp file is created 0600 in
    /// the same folder, filled, synced, then renamed over the target. If the
    /// target exists, its current contents are first copied to
    /// `<target><backupSuffix>`, also 0600. Symlinks are followed so the real
    /// file is replaced, not the link.
    public static func write(_ lines: [PgpassLine], to url: URL, backupSuffix: String? = ".pgpmana.bak") throws {
        let target = url.resolvingSymlinksInPath()
        if let suffix = backupSuffix, FileManager.default.fileExists(atPath: target.path) {
            let existing = try Data(contentsOf: target)
            try replaceAtomically(URL(fileURLWithPath: target.path + suffix), with: existing)
        }
        try replaceAtomically(target, with: Data(PgpassParser.serialize(lines).utf8))
    }

    public static func fixPermissions(at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.resolvingSymlinksInPath().path)
    }

    static func replaceAtomically(_ target: URL, with data: Data) throws {
        let dir = target.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString).tmp")

        let fd = posixOpenExclusive(tmp.path)
        guard fd >= 0 else { throw PgpassFileError.createFailed(path: tmp.path, reason: lastErrorText()) }

        let wroteAll: Bool = data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return true }
            var offset = 0
            while offset < buffer.count {
                let n = posixWrite(fd, base + offset, buffer.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
        let writeError = wroteAll ? nil : lastErrorText()
        fsync(fd)
        close(fd)

        if let writeError {
            try? FileManager.default.removeItem(at: tmp)
            throw PgpassFileError.writeFailed(path: tmp.path, reason: writeError)
        }
        if posixRename(tmp.path, target.path) != 0 {
            let reason = lastErrorText()
            try? FileManager.default.removeItem(at: tmp)
            throw PgpassFileError.renameFailed(path: target.path, reason: reason)
        }
    }
}
