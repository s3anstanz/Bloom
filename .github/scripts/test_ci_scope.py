import unittest

from ci_scope import requires_full_ci


class ScopeTests(unittest.TestCase):
    def test_routine_docs(self):
        self.assertFalse(requires_full_ci(["README.md", "docs/guide.md"]))

    def test_substantive_and_mixed_changes(self):
        for path in ["Sources/Bloom/BloomApp.swift", "Tests/BloomCoreTests/BloomCoreTests.swift",
                     "AGENTS.md", "CLAUDE.md", "docs/rules.md", "SECURITY.md", "CONTRIBUTING.md",
                     ".github/workflows/ci.yml", "scripts/install.sh", "Package.swift",
                     "Support/Info.plist", "unknown-file", "docs/sample.swift"]:
            with self.subTest(path=path):
                self.assertTrue(requires_full_ci(["README.md", path]))

    def test_empty_diff_is_conservative(self):
        self.assertTrue(requires_full_ci([]))


if __name__ == "__main__":
    unittest.main()
