#!/usr/bin/env python3
"""Exercise the build-version generator against isolated Git repositories."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


GENERATOR = Path(__file__).with_name("generate-build-version.sh").resolve()


class BuildVersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "source"
        self.root.mkdir()
        self.derived = Path(self.temp.name) / "derived"
        self.header = self.derived / "ndos_build_version.h"
        self.git("init", "-b", "master")
        (self.root / ".gitignore").write_text("ignored\n")
        (self.root / "source.txt").write_text("initial\n")
        self.commit()

    def git(self, *args):
        return subprocess.check_output(
            ["git", "-C", str(self.root), *args], text=True,
            stderr=subprocess.PIPE,
        ).strip()

    def commit(self):
        self.git("add", ".")
        self.git("-c", "user.name=Version Test", "-c",
                 "user.email=version-test@example.invalid", "commit", "-m", "fixture")

    def generate(self, version="1.1.1", **overrides):
        env = {**os.environ, "SRCROOT": str(self.root),
               "DERIVED_FILE_DIR": str(self.derived), "MARKETING_VERSION": version}
        env.update(overrides)
        return subprocess.run(["bash", str(GENERATOR)], env=env, text=True,
                              capture_output=True)

    def assert_label(self, suffix=" (master)"):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        revision = self.git("rev-parse", "--short=12", "HEAD")
        self.assertEqual(self.header.read_text(),
                         f'#pragma once\n#define NDOS_BUILD_VERSION "v1.1.1-g{revision}{suffix}"\n')
        self.assert_compiled_label(f"v1.1.1-g{revision}{suffix}")

    def assert_compiled_label(self, expected):
        literal = ''.join(f'\\{byte:03o}' for byte in expected.encode())
        harness = self.derived / "check.c"
        harness.write_text('#include "ndos_build_version.h"\n#include <string.h>\n'
                           f'int main(void) {{ return strcmp(NDOS_BUILD_VERSION, "{literal}"); }}\n')
        binary = self.derived / "check"
        subprocess.run(["clang", str(harness), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)

    def test_clean_ignored_and_unchanged_rebuild(self):
        (self.root / "ignored").write_text("ignored artifact")
        before = self.git("status", "--porcelain")
        self.assert_label()
        timestamp = self.header.stat().st_mtime_ns
        self.assert_label()
        self.assertEqual(timestamp, self.header.stat().st_mtime_ns)
        self.assertEqual(before, self.git("status", "--porcelain"))

    def test_tracked_staged_and_untracked_changes(self):
        (self.root / "source.txt").write_text("modified\n")
        self.assert_label("-dirty (master)")
        self.git("add", "source.txt")
        self.assert_label("-dirty (master)")
        self.commit()
        (self.root / "untracked").write_text("new file")
        self.assert_label("-dirty (master)")

    def test_commit_and_branch_changes(self):
        self.assert_label()
        old_header = self.header.read_text()
        (self.root / "source.txt").write_text("next commit\n")
        self.commit()
        self.assert_label()
        self.assertNotEqual(old_header, self.header.read_text())
        self.git("checkout", "-b", 'feature/"quoted"')
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(r'(feature/\042quoted\042)', self.header.read_text())
        revision = self.git("rev-parse", "--short=12", "HEAD")
        self.assert_compiled_label(f'v1.1.1-g{revision} (feature/"quoted")')

    def test_detached_head(self):
        self.git("checkout", "--detach")
        self.assert_label(" (detached)")

    def test_missing_metadata_fails(self):
        self.assertNotEqual(self.generate(version="").returncode, 0)
        non_git = Path(self.temp.name) / "non-git"
        non_git.mkdir()
        self.assertNotEqual(self.generate(SRCROOT=str(non_git)).returncode, 0)
        self.assertFalse(self.header.exists())

    def test_c_string_escaping(self):
        version = '1.1.1"\\\n??/'
        result = self.generate(version=version)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(r'v1.1.1\042\134\012\077\077/', self.header.read_text())
        revision = self.git("rev-parse", "--short=12", "HEAD")
        self.assert_compiled_label(f"v{version}-g{revision} (master)")


if __name__ == "__main__":
    unittest.main()
