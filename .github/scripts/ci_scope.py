"""Conservative path filter; uncertainty always requests full CI."""
import pathlib
import subprocess
import sys


def requires_full_ci(paths):
    if not paths:
        return True
    for path in paths:
        p = pathlib.PurePosixPath(path)
        if p.name.lower() in {"agents.md", "claude.md", "rules.md", "security.md", "contributing.md"}:
            return True
        if path == "README.md":
            continue
        if p.parts[0] == "docs" and p.suffix == ".md":
            continue
        return True
    return False


def main():
    try:
        base, head, event, force = sys.argv[1:]
        if event not in {"pull_request", "push"} or force == "true":
            return True
        if event == "pull_request":
            base = subprocess.check_output(["git", "merge-base", base, head], text=True).strip()
        changed = subprocess.check_output(
            ["git", "diff", "--no-renames", "--name-only", "-z", base, head, "--"]
        )
        return requires_full_ci(changed.decode("utf-8").rstrip("\0").split("\0") if changed else [])
    except (ValueError, UnicodeError, subprocess.CalledProcessError):
        return True


if __name__ == "__main__":
    print("full=" + str(main()).lower())
