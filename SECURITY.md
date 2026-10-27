# Security

Bloom handles your files locally and has no network code. If you find a way it could leak, damage or overwrite files, or run something it shouldn't, please report it privately.

## Reporting a vulnerability

Use [Report a vulnerability](https://github.com/s3anstanz/Bloom/security/advisories/new) on this repository's Security tab. Please don't open a public issue for security problems.

Include what you found, the steps to reproduce it, and your macOS version. You'll get a reply within a week.

## Supported versions

Only the latest commit on `main` gets security fixes.

## File-processing boundaries

Conversions are staged in private directories and published without replacing an existing path. Bloom rejects output paths beneath other-user-owned ancestors, non-sticky shared writable directories, or allow ACLs, including inherited grants. This conservative check can reject shared folders; move the input to a private folder before converting it. Processes running as your own user, administrators, and filesystems that do not enforce these permissions are outside this isolation boundary.

Archive subprocesses run under a macOS sandbox policy that denies network access and limits writes to the private extraction folder and local diagnostic log. This is not a resource quota: archive expansion, converter memory use, and processing time are not currently bounded. Other document/media importers are not isolated by this archive policy; the source-code offline guard does not prove that platform importers never fetch external resources.

Problem-report URLs contain build information, petal and file-type metadata, and a fixed error sentence written by Bloom. They exclude file names, paths, free-form tool diagnostics and archive member contents. Opening the form sends its prefilled fields to GitHub through the browser before an issue is submitted.
