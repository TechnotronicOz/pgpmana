import Foundation
import Darwin

/// Calls `onChange` on the main queue when the file is written, replaced,
/// deleted, or has its permissions changed.
///
/// Editors (and pgpmana itself) often save by writing a new file and renaming
/// it over the old one. The watcher follows that by re-opening the path after
/// a delete or rename. If the file doesn't exist, it checks again every two
/// seconds until it does.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var retry: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit {
        stop()
    }

    func stop() {
        retry?.cancel()
        retry = nil
        source?.cancel()
        source = nil
    }

    private func start() {
        stop()
        let fd = Darwin.open(url.resolvingSymlinksInPath().path, O_EVTONLY)
        guard fd >= 0 else {
            scheduleRetry()
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .link],
            queue: .main
        )
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            let events = src.data
            self.onChange()
            if events.contains(.delete) || events.contains(.rename) {
                // The path now points at a different file (or none). Watch it again.
                DispatchQueue.main.async { [weak self] in self?.start() }
            }
        }
        src.setCancelHandler { Darwin.close(fd) }
        source = src
        src.resume()
    }

    private func scheduleRetry() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let existed = FileManager.default.fileExists(atPath: self.url.path)
            self.start()
            // It just appeared: let the store pick it up.
            if existed { self.onChange() }
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
