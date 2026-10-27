import Darwin
import Foundation

/// Converters write only inside private sibling directories. A completed result is published with an exclusive
/// rename, so a destination created by another process (including a dangling symlink) is never replaced.
final class OutputTransaction: @unchecked Sendable {
    @TaskLocal static var current: OutputTransaction?

    private struct Output {
        let staged: URL
        let folder: URL
        let base: String
        let ext: String?
    }

    private let lock = NSLock()
    private var outputs: [Output] = []
    private var directories: [URL] = []

    static func perform(_ operation: () async throws -> [URL]) async throws -> [URL] {
        // apply(.compress) delegates to compress; keep one transaction for the whole selection.
        if current != nil { return try await operation() }
        let transaction = OutputTransaction()
        defer { transaction.cleanUp() }
        return try await $current.withValue(transaction) {
            try transaction.publish(try await operation())
        }
    }

    func stage(in folder: URL, base: String, ext: String?) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        let folder = folder.resolvingSymlinksInPath()
        try validateAncestry(of: folder)
        let directory = folder.appendingPathComponent(".bloom-\(UUID().uuidString)", isDirectory: true)
        // mkdir fails on any existing entry, unlike createDirectory, and requests owner-only access from the start.
        guard mkdir(directory.path, mode_t(S_IRWXU)) == 0 else { throw posixError() }
        directories.append(directory)
        let file = directory.appendingPathComponent(base)
        let staged = ext.map { file.appendingPathExtension($0) } ?? file
        outputs.append(Output(staged: staged, folder: folder, base: base, ext: ext))
        return staged
    }

    func publish(_ results: [URL]) throws -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        var published: [URL] = []
        do {
            for result in results {
                guard let output = outputs.first(where: { $0.staged == result }) else {
                    throw ConversionError("Couldn’t find the result to save.")
                }
                while true {
                    let destination = Engine.uniqueURL(in: output.folder, base: output.base, ext: output.ext)
                    if renamex_np(result.path, destination.path, UInt32(RENAME_EXCL)) == 0 {
                        published.append(destination)
                        break
                    }
                    // A file may have appeared after uniqueURL checked. Only collisions may be retried.
                    let code = errno
                    guard code == EEXIST || code == ENOTEMPTY else { throw posixError(code) }
                }
            }
        } catch {
            // Published paths are public again. Never delete them on rollback: somebody else may have replaced them.
            if !published.isEmpty {
                throw ConversionError("Couldn’t save all results. Earlier results were kept.")
            }
            throw error
        }
        return published
    }

    func cleanUp() {
        lock.lock()
        defer { lock.unlock() }
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories.removeAll()
        outputs.removeAll()
    }

    static func entryExists(at url: URL) -> Bool {
        var info = stat()
        // lstat sees dangling symlinks. This is only a naming hint: exclusive rename enforces no replacement.
        return lstat(url.path, &info) == 0
    }

    private func posixError(_ code: Int32 = errno) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    /// Owner-only staging is insufficient when another user can replace its entry through a shared parent.
    /// Use canonical paths and reject ancestors owned or replaceable by other users. Sticky directories such as
    /// /tmp protect our entries; another process running as this same user is outside this permission boundary.
    private func validateAncestry(of folder: URL) throws {
        var ancestor = folder
        while true {
            var info = stat()
            guard lstat(ancestor.path, &info) == 0 else { throw posixError() }
            let writableByOthers = info.st_mode & mode_t(S_IWGRP | S_IWOTH) != 0
            let sticky = info.st_mode & mode_t(S_ISVTX) != 0
            guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
                info.st_uid == geteuid() || info.st_uid == 0,
                !writableByOthers || sticky
            else {
                throw ConversionError("Save this file in a folder only you can change, then try again.")
            }
            try validateACL(of: ancestor)
            if ancestor.path == "/" { break }
            ancestor.deleteLastPathComponent()
        }
    }

    private func validateACL(of directory: URL) throws {
        guard let acl = acl_get_file(directory.path, ACL_TYPE_EXTENDED) else {
            let code = errno
            // Darwin also returns ENOENT when an existing directory has no extended ACL. Distinguish that from a
            // missing directory; every other retrieval error fails closed.
            if code == ENOENT {
                var info = stat()
                if lstat(directory.path, &info) == 0 { return }
            }
            throw posixError(code)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw posixError() }
        var entry: acl_entry_t?
        var cursor = Int32(ACL_FIRST_ENTRY.rawValue)
        while acl_get_entry(acl, cursor, &entry) == 0 {
            cursor = Int32(ACL_NEXT_ENTRY.rawValue)
            var tag = ACL_UNDEFINED_TAG
            guard let entry, acl_get_tag_type(entry, &tag) == 0 else { throw posixError() }
            // Conservatively reject allow ACEs, including inherited ones: POSIX mode bits alone do not constrain
            // them, and mkdir(0700) can still inherit access grants. Deny-only ACLs (common on home folders) are safe.
            guard tag != ACL_EXTENDED_ALLOW else {
                throw ConversionError("This folder has shared permissions. Save the file in a private folder and try again.")
            }
        }
    }
}
