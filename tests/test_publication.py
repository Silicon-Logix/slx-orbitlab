# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Regression checks for publication leaks, including Git index and historical blobs."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from publication_audit import git_audit, publication_errors


class PublicationTests(unittest.TestCase):
    def test_private_and_generated_files_are_rejected(self):
        for name in ("private/core/mission.cpp", "src/copy.obj", "scene/original.blend", "workspace/session.sqlite", ".env.production", "backend/__pycache__/module.pyc"):
            self.assertTrue(publication_errors(Path(name), b""), name)

    def test_approved_models_and_abi_are_allowed(self):
        for name in ("SLX_OrbitLab_3D/exports/Component_Power.glb", "core/include/SiliconLogiX/OrbitLab/Core.h"):
            self.assertEqual(publication_errors(Path(name), b"approved", github=True), [])

    def test_sdk_is_excluded_from_github_source(self):
        path = Path("sdk/windows-mingw/SiliconLogiX.OrbitLab.Core.dll.a")
        self.assertEqual(publication_errors(path, b"approved", github=False), [])
        self.assertTrue(publication_errors(path, b"approved", github=True))

    def test_renamed_implementation_is_rejected(self):
        source = b"struct " + b"SlxMission { int private_state; };"
        self.assertTrue(publication_errors(Path("src/renamed.cpp"), source))

    def test_credentials_and_user_paths_are_rejected(self):
        fixtures = [b"gh" + b"p_" + b"x" * 36, b"/home/" + b"developer/project/file.cpp", b"C:/" + b"Users/developer/project/file.cpp"]
        for data in fixtures:
            self.assertTrue(publication_errors(Path("docs/review.txt"), data))

    def test_internal_notes_are_rejected(self):
        self.assertTrue(publication_errors(Path("src/component.cpp"), b"// TO" + b"DO: finish this"))

    def test_ignored_tracked_bytes_are_audited(self):
        with tempfile.TemporaryDirectory(prefix="slx-publication-index-") as directory:
            root = Path(directory)
            self.git(root, "init", "--initial-branch=main")
            (root / "private").mkdir()
            (root / "private/mission.cpp").write_text("private data")
            self.git(root, "add", "private/mission.cpp")
            (root / ".gitignore").write_text("private/\n")
            state, errors = git_audit(root, github=True)
            self.assertEqual(state["tracked_files"], 1)
            self.assertTrue(any("Private/generated" in error for error in errors))

    def test_removed_private_history_is_still_rejected(self):
        with tempfile.TemporaryDirectory(prefix="slx-publication-history-") as directory:
            root = Path(directory)
            self.git(root, "init", "--initial-branch=main")
            (root / "private").mkdir()
            (root / "private/mission.cpp").write_text("private data")
            self.git(root, "add", "--all")
            self.git(root, "-c", "user.name=Publication test", "-c", "user.email=test@example.invalid", "commit", "-m", "Fixture")
            self.git(root, "rm", "private/mission.cpp")
            self.git(root, "-c", "user.name=Publication test", "-c", "user.email=test@example.invalid", "commit", "-m", "Remove fixture")
            state, errors = git_audit(root, github=True)
            self.assertGreater(state["history_blobs"], 0)
            self.assertTrue(any(error.startswith("History:") for error in errors))

    @staticmethod
    def git(root, *arguments):
        return subprocess.run(["git", "-C", str(root), *arguments], capture_output=True, check=True)


if __name__ == "__main__":
    unittest.main()
