import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MOCK_TOOL = r'''
import os
from pathlib import Path
import sys

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ["PACKAGING_TEST_ROOT"])
if tool == "swift":
    directory = Path(args[args.index("--build-path") + 1])
    directory.mkdir(parents=True, exist_ok=True)
    for name in ("TaskTickApp", "tasktick"):
        binary = directory / name
        binary.write_text("#!/bin/sh\nexit 0\n")
        binary.chmod(0o755)
    (directory / "TaskTick_TaskTickCore.bundle").mkdir(exist_ok=True)
elif tool == "xcrun":
    print("26.0")
elif tool == "codesign":
    print("Signature=adhoc")
elif tool == "vtool":
    pass
elif tool == "hdiutil":
    destination = next(arg for arg in args if arg.endswith(".dmg"))
    Path(destination).write_text("mock DMG")
elif tool == "osascript":
    (root / "dialog-default").write_text(args[1])
    sys.stdout.write(os.environ.get("PACKAGING_TEST_VERSION", ""))
elif tool in ("git", "gh", "curl"):
    with (root / "publisher-called").open("a") as output:
        output.write(tool + "\n")
    sys.exit(70)
else:
    sys.exit("Unexpected tool: " + tool)
'''


class LocalPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="tasktick-local-packaging-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        scripts = self.root / "scripts"
        scripts.mkdir()
        for name in ("release.sh", "package-local.sh"):
            shutil.copy(PROJECT_ROOT / "scripts" / name, scripts / name)

        commands = self.root / "mock-bin"
        commands.mkdir()
        runner = commands / "mock-tool"
        runner.write_text("#!" + sys.executable + "\n" + MOCK_TOOL)
        runner.chmod(0o755)
        for name in ("swift", "xcrun", "codesign", "vtool", "hdiutil",
                     "osascript", "git", "gh", "curl"):
            (commands / name).symlink_to(runner)
        self.environment = {
            **os.environ,
            "PATH": str(commands) + os.pathsep + os.environ["PATH"],
            "PACKAGING_TEST_ROOT": str(self.root),
            "GITEE_TOKEN": "dummy-test-token",
        }

    def run_script(self, name, *arguments, version_input=""):
        return subprocess.run(
            ["/bin/bash", str(self.root / "scripts" / name), *arguments],
            env={**self.environment, "PACKAGING_TEST_VERSION": version_input},
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def assert_local_build(self, result, version):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root / "publisher-called").exists())
        for architecture in ("arm64", "x86_64"):
            self.assertTrue((self.root / ".release" /
                             f"TaskTick-{version}-{architecture}.dmg").exists())
            plist_path = (self.root / ".release" / architecture /
                          "TaskTick.app/Contents/Info.plist")
            with plist_path.open("rb") as source:
                info = plistlib.load(source)
            self.assertEqual(info["CFBundleShortVersionString"], version)
            self.assertEqual(info["CFBundleIdentifier"], "com.lifedever.TaskTick")

    def test_local_build_without_terminal_never_publishes(self):
        result = self.run_script("release.sh", "1.26.0", "--local-only")
        self.assert_local_build(result, "1.26.0")

    def test_local_only_wins_over_yes(self):
        result = self.run_script("release.sh", "1.26.0", "--yes", "--local-only")
        self.assert_local_build(result, "1.26.0")

    def test_normal_release_still_requires_terminal_or_yes(self):
        result = self.run_script("release.sh", "1.26.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stdin is not a TTY", result.stdout)
        self.assertFalse((self.root / "publisher-called").exists())

    def test_dialog_remembers_last_version(self):
        result = self.run_script("package-local.sh", version_input="1.26.1")
        self.assert_local_build(result, "1.26.1")
        result = self.run_script("package-local.sh", version_input="1.26.2")
        self.assert_local_build(result, "1.26.2")
        self.assertEqual((self.root / "dialog-default").read_text(), "1.26.1")
        self.assertEqual((self.root / ".local/release-version").read_text(), "1.26.2\n")

    def test_cancel_does_not_build(self):
        result = self.run_script("package-local.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("已取消打包", result.stdout)
        self.assertFalse((self.root / ".release").exists())
        self.assertFalse((self.root / ".local/release-version").exists())

    def test_invalid_version_does_not_build(self):
        result = self.run_script("package-local.sh", "1.26.0; echo unexpected")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / ".release").exists())

    def test_explicit_version_does_not_open_dialog(self):
        result = self.run_script("package-local.sh", "1.26.0")
        self.assert_local_build(result, "1.26.0")
        self.assertFalse((self.root / "dialog-default").exists())


if __name__ == "__main__":
    unittest.main()
