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
                "-D", "OUTPUT=\(folder.resolvingSymlinksInPath().path)",
                "-D", "ERROR_LOG=\(errorLog.resolvingSymlinksInPath().path)",
                "-p", profile, tool.path,
            ] + arguments
    }
}
