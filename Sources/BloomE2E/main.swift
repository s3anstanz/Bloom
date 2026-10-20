import Foundation

// Line by line, so the CI log shows each step as it happens.
setvbuf(stdout, nil, _IOLBF, 0)

var arguments = Array(CommandLine.arguments.dropFirst())
guard let flag = arguments.firstIndex(of: "--out"), arguments.indices.contains(flag + 1) else {
    FileHandle.standardError.write(Data("Usage: BloomE2E --out <folder> [--matrix] [journey or sample ...]\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[flag + 1])
arguments.removeSubrange(flag...(flag + 1))
let matrix = arguments.contains("--matrix")
arguments.removeAll { $0 == "--matrix" }
let passed = await Suite(output: output).run(only: Set(arguments), matrix: matrix)
exit(passed ? 0 : 1)
