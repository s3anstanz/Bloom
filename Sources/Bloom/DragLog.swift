import os

/// What happens to each drag, in the Mac's unified log: open Console and search for com.westfalllabs.bloom, or run
/// `log show --last 5m --predicate 'subsystem == "com.westfalllabs.bloom"'`. Events only, never a file's name or
/// folder, and it stays on this Mac.
let dragLog = Logger(subsystem: "com.westfalllabs.bloom", category: "drag")
