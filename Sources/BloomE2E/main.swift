import Foundation

// Line by line, so the CI log shows each step as it happens.
setvbuf(stdout, nil, _IOLBF, 0)

let arguments = Array(CommandLine.arguments.dropFirst())
guard let flag = arguments.firstIndex(of: "--out"), arguments.indices.contains(flag + 1) else {
    FileHandle.standardError.write(Data("Usage: BloomE2E --out <folder> [journey ...]\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[flag + 1])
var names = arguments
names.removeSubrange(flag...(flag + 1))
let passed = await Suite(output: output).run(only: Set(names))
exit(passed ? 0 : 1)
