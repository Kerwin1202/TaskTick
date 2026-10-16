from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/release-notes.sh"


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="tasktick-release-notes-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Release Tester")
        self.git("config", "user.email", "release@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "tag.gpgsign", "false")

    def git(self, *arguments):
        return subprocess.check_output(
            ["git", *arguments], cwd=self.root, text=True, stderr=subprocess.PIPE
        ).strip()

    def commit(self, message):
        self.git("commit", "--allow-empty", "-qm", message)
        return self.git("rev-parse", "HEAD")

    def notes(self, tag, commit="HEAD"):
        return subprocess.check_output(
            ["bash", str(SCRIPT), tag, commit, "example/TaskTick"],
            cwd=self.root, text=True, stderr=subprocess.PIPE,
        )

    def test_annotated_tag_includes_message_and_only_new_commits(self):
        self.commit("old change")
        self.git("tag", "v1.26.3")
        first = self.commit("first new change")
        second = self.commit("second new change")
        self.git("tag", "-a", "v1.26.4", "-m", "新版说明\n\n修复问题并优化功能。")

        notes = self.notes("v1.26.4")
        self.assertIn("新版说明\n\n修复问题并优化功能。", notes)
        self.assertIn("first new change", notes)
        self.assertIn("second new change", notes)
        self.assertNotIn("old change", notes)
        self.assertIn(f"https://github.com/example/TaskTick/commit/{first}", notes)
        self.assertIn(f"https://github.com/example/TaskTick/commit/{second}", notes)
        self.assertIn("Release Tester", notes)
        self.assertIn("compare/v1.26.3...v1.26.4", notes)

    def test_lightweight_tag_does_not_treat_commit_message_as_annotation(self):
        self.commit("old change")
        self.git("tag", "v1.26.3")
        self.commit("new change")
        self.git("tag", "v1.26.4")

        notes = self.notes("v1.26.4")
        self.assertNotIn("## 版本说明", notes)
        self.assertEqual(notes.count("new change"), 1)

    def test_first_release_includes_entire_history(self):
        self.commit("initial change")
        self.commit("next change")
        self.git("tag", "v1.0.0")

        notes = self.notes("v1.0.0")
        self.assertIn("首次发布", notes)
        self.assertIn("initial change", notes)
        self.assertIn("next change", notes)
        self.assertNotIn("/compare/", notes)

    def test_new_version_without_tag_can_have_no_new_commits(self):
        self.commit("existing release")
        self.git("tag", "v1.26.3")

        notes = self.notes("v1.26.4")
        self.assertIn("两个版本之间没有新的提交", notes)
        self.assertNotIn("existing release", notes)
        self.assertIn("compare/v1.26.3...v1.26.4", notes)

    def test_rebuild_old_tag_ignores_newer_head(self):
        self.commit("base change")
        self.git("tag", "v1.26.2")
        old_commit = self.commit("old version change")
        self.git("tag", "v1.26.3")
        self.commit("future change")
        self.git("tag", "v1.26.4")

        notes = self.notes("v1.26.3", old_commit)
        self.assertIn("old version change", notes)
        self.assertNotIn("future change", notes)
        self.assertIn("compare/v1.26.2...v1.26.3", notes)

    def test_previous_tag_follows_release_branch_and_includes_merged_commits(self):
        self.commit("base change")
        self.git("tag", "v1.26.3")
        self.git("checkout", "-qb", "feature")
        self.commit("merged feature")
        self.git("tag", "v9.0.0")
        self.git("checkout", "-q", "main")
        self.commit("main change")
        self.git("merge", "--no-ff", "feature", "-m", "merge feature")
        self.git("tag", "v1.26.4")

        notes = self.notes("v1.26.4")
        self.assertIn("compare/v1.26.3...v1.26.4", notes)
        self.assertIn("merged feature", notes)
        self.assertIn("main change", notes)
        self.assertIn("merge feature", notes)


if __name__ == "__main__":
    unittest.main()
