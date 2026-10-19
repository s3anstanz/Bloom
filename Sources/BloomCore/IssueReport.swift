import Foundation

/// One of Bloom's GitHub issue forms, filled in with what Bloom knows. The app opens it in the browser, where the
/// person reads, edits and submits it; Bloom itself sends nothing.
public struct IssueReport: Equatable {
    public struct Field: Equatable {
        public let id: String
        public let value: String
    }

    /// A petal that failed: what was dropped on it, and what Bloom said.
    public struct Failure: Equatable {
        public let petal: String
        public let mode: Mode
        public let files: [URL]
        public let message: String

        public init(petal: String, mode: Mode, files: [URL], message: String) {
            self.petal = petal
            self.mode = mode
            self.files = files
            self.message = message
        }
    }

    /// The form's file in `.github/ISSUE_TEMPLATE`.
    public let template: String
    public let title: String
    /// Values for the form's fields, keyed by each field's `id` there.
    public let fields: [Field]

    public var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "template", value: template)]
        if !title.isEmpty { items.append(URLQueryItem(name: "title", value: title)) }
        return items + fields.map { URLQueryItem(name: $0.id, value: $0.value) }
    }

    /// A bug report about `failure`, or about nothing in particular when no petal has failed.
    public static func problem(_ failure: Failure?, build: BuildInfo) -> IssueReport {
        let buildFields = [
            Field(id: "bloom", value: build.bloom),
            Field(id: "macos", value: build.macOS),
            Field(id: "mac", value: build.chip),
        ]
        guard let failure else { return IssueReport(template: "bug_report.yml", title: "", fields: buildFields) }
        let types = fileTypes(failure.files)
        let dropped = failure.files.count == 1 ? "a file (\(types))" : "\(failure.files.count) files (\(types))"
        let story = "I dropped \(dropped) on \(failure.petal) in the \(flower(failure.mode)) flower, and it failed."
        let failureFields = [
            Field(id: "what-happened", value: "\(story)\n\nWhat I expected:\n"),
            Field(id: "file-type", value: types),
            Field(id: "output", value: redacting(failure.message, files: failure.files)),
        ]
        return IssueReport(template: "bug_report.yml", title: "\(failure.petal) failed on \(types)", fields: failureFields + buildFields)
    }

    public static func feedback(build: BuildInfo) -> IssueReport {
        IssueReport(template: "idea.yml", title: "", fields: [Field(id: "bloom", value: build.bloom)])
    }

    private static func flower(_ mode: Mode) -> String {
        switch mode {
        case .convert: return "⇧ Convert"
        case .tools: return "⌘ Tools"
        case .actions: return "⌃ Actions"
        }
    }

    /// "JPG", or "JPG, PNG" for a mixed selection.
    private static func fileTypes(_ files: [URL]) -> String {
        var types: [String] = []
        for file in files {
            let type = file.hasDirectoryPath ? "folder" : file.pathExtension.isEmpty ? "no extension" : file.pathExtension.uppercased()
            if !types.contains(type) { types.append(type) }
        }
        return types.joined(separator: ", ")
    }

    /// Bloom's messages and the output of the tools it runs can name the dropped files and their folders; reports never do.
    private static func redacting(_ message: String, files: [URL]) -> String {
        var text = message
        let parents = files.map { $0.deletingLastPathComponent() }
        let folders = Set(parents.map(\.path) + parents.map { $0.resolvingSymlinksInPath().path })
        for folder in folders.sorted(by: { $0.count > $1.count }) where folder != "/" {
            text = text.replacingOccurrences(of: folder, with: "[folder]")
        }
        text = text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        for file in files {
            text = text.replacingOccurrences(of: file.lastPathComponent, with: "[file]")
            // Results are named after the original, like "photo (compressed).jpg".
            let stem = file.deletingPathExtension().lastPathComponent
            if stem.count >= 3 { text = text.replacingOccurrences(of: stem, with: "[file]") }
        }
        return String(text.prefix(500))
    }
}

/// The Bloom build and the Mac a report comes from.
public struct BuildInfo: Equatable {
    public let version: String?
    public let commit: String?
    public let macOS: String
    public let chip: String

    public init(version: String?, commit: String?, macOS: String, chip: String) {
        self.version = version
        self.commit = commit
        self.macOS = macOS
        self.chip = chip
    }

    /// Reads the app bundle, where `scripts/bundle.sh` records the commit Bloom was built from, and this Mac.
    public static func current(bundle: Bundle = .main) -> BuildInfo {
        let info = bundle.infoDictionary
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
            .replacingOccurrences(of: "Build ", with: "")
        return BuildInfo(
            version: info?["CFBundleShortVersionString"] as? String,
            commit: info?["BloomCommit"] as? String,
            macOS: macOS,
            chip: cpuBrand() ?? "Unknown"
        )
    }

    /// "0.3.0 (a554c98)".
    var bloom: String {
        guard let version else { return "Run from source with swift run" }
        return commit.map { "\(version) (\($0))" } ?? version
    }

    /// "Apple M2" on Apple silicon, the Intel model name on an Intel Mac.
    private static func cpuBrand() -> String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var brand = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0) == 0 else { return nil }
        return brand.withUnsafeBufferPointer { buffer in buffer.baseAddress.map { String(cString: $0) } }
    }
}
