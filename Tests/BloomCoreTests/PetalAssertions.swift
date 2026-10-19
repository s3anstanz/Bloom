import BloomCore
import BloomFixtures
import XCTest

/// Runs every Convert and Tools petal offered for `files` the way a drop does, and fails for any petal whose result is
/// missing or won't open, or that changed the original. Remove BG is covered separately because it depends on the Mac's
/// Vision support.
func assertEveryPetalWorks(for files: [URL], file: StaticString = #filePath, line: UInt = #line) async {
    let originals = Originals(files)
    for mode in [Mode.convert, .tools] {
        // A petal with choices does what one of them does, so each choice stands in for it.
        let petals = await WheelCatalog.items(for: files, mode: mode).flatMap { $0.choices.isEmpty ? [$0] : $0.choices }
        for item in petals {
            if case .tool(.removeBackground) = item.operation { continue }
            if case .action = item.operation { continue }
            let label = "\(files.map(\.lastPathComponent).joined(separator: " + ")) → \(item.title)"
            do {
                let outputs = try await Engine.run(item.operation, on: files) ?? []
                XCTAssertFalse(outputs.isEmpty, "\(label): no output", file: file, line: line)
                for output in outputs {
                    if let problem = await defect(in: output) {
                        XCTFail("\(label): \(problem)", file: file, line: line)
                    }
                }
            } catch is AlreadySmall {
                // A small generated sample can come out bigger; CompressionTests checks that real files shrink.
            } catch {
                XCTFail("\(label): \(error.localizedDescription)", file: file, line: line)
            }
            if let problem = originals.change(in: files) {
                XCTFail("\(label): \(problem)", file: file, line: line)
                return
            }
        }
    }
}
