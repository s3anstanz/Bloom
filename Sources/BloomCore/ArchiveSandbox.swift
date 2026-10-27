import Darwin
import Foundation

/// A second boundary around system archivers: archive entries cannot write outside the private extraction folder.
enum ArchiveSandbox {
    static func confine(_ process: Process, to folder: URL, diagnostics errorLog: URL) throws {
        guard let tool = process.executableURL else { throw ConversionError("Couldn’t start the archive tool.") }
        let arguments = process.arguments ?? []
        // Parameters keep paths out of the policy language, including quotes, backslashes and control characters.
        let profile = """
            (version 1)
            (allow default)
            (deny network*)
            (deny file-write*)
            (allow file-write*
                (subpath (param "OUTPUT"))
                (literal (param "ERROR_LOG"))
                (literal "/dev/null"))
            """
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments =
            [
                "-D", "OUTPUT=\(try realPath(folder))",
                "-D", "ERROR_LOG=\(try realPath(errorLog))",
                "-p", profile, tool.path,
            ] + arguments
    }

    /// Foundation presents `/private/var` as `/var` on macOS. Seatbelt compares the kernel's real path, so use
    /// `realpath` rather than the display-oriented Foundation spelling for policy parameters.
    private static func realPath(_ url: URL) throws -> String {
        guard let path = realpath(url.path, nil) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { free(path) }
        return String(cString: path)
    }
}
