"""Exercise the actual workflow Apple publishing scripts with a fake App Store Connect API.

Run with Python, PyYAML, Bash and jq installed:
    python .github/tests/test_apple_publishing.py
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


REPO = Path(__file__).resolve().parents[2]
WORKFLOW = REPO / ".github/workflows/publish-app.yml"
JOBS = (("IOS", "build-ios"), ("MAC_OS", "build-macos"))

# Shell functions replace only the external service and sleep. The workflow's
# Bash control flow and jq filters execute unchanged, without Apple credentials.
MOCK_COMMANDS = r'''
app-store-connect() {
    if [[ "$1 $2" == "apps list" ]]; then
        [[ " $* " == *" --bundle-id-identifier run.chameleon.gui "* ]] || return 90
        [[ " $* " == *" --strict-match-identifier "* ]] || return 90
        [[ " $* " == *" --json "* ]] || return 90
        cat app.json
    elif [[ "$1 $2" == "apps app-store-versions" ]]; then
        [[ " $* " == *" 123456 --platform $TEST_PLATFORM --json "* ]] || return 93
        cat versions.json
    elif [[ "$1 $2" == "builds list" ]]; then
        for filter in "--app-id 123456" "--platform $TEST_PLATFORM" \
                      "--build-version-number 694" "--processing-state VALID" "--json"; do
            [[ " $* " == *" $filter "* ]] || return 91
        done
        echo query >> queries
        if [[ "$TEST_CASE" == retry && ! -f polled ]]; then
            touch polled
            echo '[]'
        else
            cat builds.json
        fi
        # Even valid-looking stdout must not hide a failed API call.
        if [[ "$TEST_CASE" == api_error ]]; then return 7; fi
    elif [[ "$1 $2 $3" == "builds submit-to-testflight build-694" ]]; then
        case "$TEST_CASE" in
            submitted) echo "Beta review state: WAITING_FOR_REVIEW" ;;
            in_review) echo "returned 422: Another build is in review." >&2; return 1 ;;
            *) echo "returned 500: Internal error" >&2; return 1 ;;
        esac
    elif [[ "$*" == "beta-groups add-build build-694 --beta-group Open beta testing" ]]; then
        touch added
    else
        return 92
    fi
}
sleep() { echo "$*" >> sleeps; }
'''


def version(state, version_string):
    return {"attributes": {"versionString": version_string, "appVersionState": state}}


class ApplePublishingTest(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.safe_load(WORKFLOW.read_text())
        self.bash = shutil.which("bash")
        self.assertIsNotNone(self.bash, "Bash must be installed")
        self.assertIsNotNone(shutil.which("jq"), "jq must be installed")

    def step(self, job, prefix):
        return next(
            step for step in self.workflow["jobs"][job]["steps"]
            if step.get("name", "").startswith(prefix)
        )

    def run_step(self, work, step, platform, case, files, env=None):
        """Runs a workflow step's script in `work` and returns (result, $GITHUB_ENV)."""
        self.assertEqual(step["shell"], "bash")
        script = step["run"].replace("${{ github.run_number }}", "694")
        for name, content in files.items():
            (work / name).write_text(content)
        (work / "AuthKey.p8").write_text("test-placeholder")
        (work / "github-env").touch()
        (work / "step.sh").write_text(MOCK_COMMANDS + script, newline="\n")
        result = subprocess.run(
            [self.bash, "--noprofile", "--norc", "-eo", "pipefail", "step.sh"],
            cwd=work,
            env=dict(
                os.environ,
                TEST_PLATFORM=platform,
                TEST_CASE=case,
                APP_ID="123456",
                GITHUB_ENV=(work / "github-env").as_posix(),
                GITHUB_WORKSPACE=REPO.as_posix(),
                **(env or {}),
            ),
            capture_output=True, text=True, timeout=10,
        )
        return result, (work / "github-env").read_text()

    def test_version(self):
        released = version("READY_FOR_DISTRIBUTION", "1.4.754")
        # case: (apps, App Store versions, pubspec version, expected version or None on failure)
        cases = {
            "first_release": ([{"id": "123456"}], [], "1.4.0", "1.4.0"),
            "reuse_open": ([{"id": "123456"}], [
                released, version("PREPARE_FOR_SUBMISSION", "1.4.755"),
            ], "1.4.0", "1.4.755"),
            "bump_after_release": ([{"id": "123456"}], [
                version("REPLACED_WITH_NEW_VERSION", "1.4.10"), version("READY_FOR_DISTRIBUTION", "1.4.9"),
            ], "1.4.0", "1.4.11"),
            "pubspec_bump": ([{"id": "123456"}], [
                version("WAITING_FOR_REVIEW", "1.4.755"),
            ], "1.5.0", "1.5.0"),
            "ambiguous_open": ([{"id": "123456"}], [
                version("IN_REVIEW", "1.4.1"), version("PREPARE_FOR_SUBMISSION", "1.4.2"),
            ], "1.4.0", None),
            "missing_app": ([], [released], "1.4.0", None),
            "ambiguous_app": ([{"id": "123456"}] * 2, [released], "1.4.0", None),
        }
        for platform, job in JOBS:
            step = self.step(job, "Pick ")
            for case, (apps, versions, pubspec, expected) in cases.items():
                with self.subTest(platform=platform, case=case), \
                        tempfile.TemporaryDirectory() as directory:
                    result, output = self.run_step(Path(directory), step, platform, case, {
                        "app.json": json.dumps(apps),
                        "versions.json": json.dumps(versions),
                        "pubspec.yaml": f"name: chameleonultragui\nversion: {pubspec}+0\n",
                    })
                    if expected:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(output, f"APP_ID=123456\nVERSION={expected}\n")
                    else:
                        self.assertNotEqual(result.returncode, 0, result.stdout)
                        self.assertEqual(output, "")

    def test_polling(self):
        for platform, job in JOBS:
            step = self.step(job, "Wait for processed")
            self.assertEqual(step["timeout-minutes"], 30)
            for case in ("ready", "retry", "api_error", "invalid_json", "ambiguous_build"):
                with self.subTest(platform=platform, case=case), \
                        tempfile.TemporaryDirectory() as directory:
                    work = Path(directory)
                    builds = [{"id": "build-694", "attributes": {"version": "694"}}]
                    if case == "ambiguous_build":
                        builds *= 2
                    result, output = self.run_step(work, step, platform, case, {
                        "builds.json": "invalid json" if case == "invalid_json" else json.dumps(builds),
                    })
                    if case in ("ready", "retry"):
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(output, "BUILD_ID=build-694\n")
                        queries = (work / "queries").read_text().splitlines()
                        self.assertEqual(len(queries), 2 if case == "retry" else 1)
                        if case == "retry":
                            self.assertEqual((work / "sleeps").read_text(), "30\n")
                    else:
                        self.assertNotEqual(result.returncode, 0, result.stdout)
                        self.assertEqual(output, "")

    def test_testflight(self):
        for platform, job in JOBS:
            step = self.step(job, "Submit to TestFlight")
            for case in ("submitted", "in_review", "api_error"):
                with self.subTest(platform=platform, case=case), \
                        tempfile.TemporaryDirectory() as directory:
                    work = Path(directory)
                    result, _ = self.run_step(work, step, platform, case, {}, env={
                        "BUILD_ID": "build-694", "VERSION": "1.4.757",
                    })
                    self.assertEqual(result.returncode, 1 if case == "api_error" else 0, result.stdout)
                    # Only a build that was actually submitted joins the open beta group.
                    self.assertEqual((work / "added").exists(), case == "submitted")
                    if case == "in_review":
                        self.assertIn("another 1.4.757 build is still in beta review", result.stdout)

    def test_testflight_does_not_wait_for_app_store(self):
        for _, job in JOBS:
            names = [step.get("name") for step in self.workflow["jobs"][job]["steps"]]
            self.assertLess(names.index("Submit to TestFlight"), names.index("Submit to App Store"))
            self.assertIn("!cancelled()", self.step(job, "Submit to App Store")["if"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
