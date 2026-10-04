"""Exercise the actual workflow polling scripts with a fake App Store Connect API.

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


WORKFLOW = Path(__file__).resolve().parents[1] / "workflows/publish-app.yml"

# Shell functions replace only the external service and sleep. The workflow's
# Bash control flow and jq filters execute unchanged, without Apple credentials.
MOCK_COMMANDS = r'''
app-store-connect() {
    if [[ "$1 $2" == "apps list" ]]; then
        [[ " $* " == *" --bundle-id-identifier run.chameleon.gui "* ]] || return 90
        [[ " $* " == *" --strict-match-identifier "* ]] || return 90
        [[ " $* " == *" --json "* ]] || return 90
        cat app.json
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
    else
        return 92
    fi
}
sleep() { echo "$*" >> sleeps; }
'''


class ApplePublishingTest(unittest.TestCase):
    def test_polling(self):
        workflow = yaml.safe_load(WORKFLOW.read_text())
        bash = shutil.which("bash")
        self.assertIsNotNone(bash, "Bash must be installed")
        self.assertIsNotNone(shutil.which("jq"), "jq must be installed")

        for platform, job in (("IOS", "build-ios"), ("MAC_OS", "build-macos")):
            step = next(
                step for step in workflow["jobs"][job]["steps"]
                if step.get("name", "").startswith("Wait for processed")
            )
            self.assertEqual(step["timeout-minutes"], 30)
            self.assertEqual(step["shell"], "bash")
            script = step["run"].replace("${{ github.run_number }}", "694")
            for case in (
                "ready", "retry", "api_error", "invalid_json",
                "missing_app", "ambiguous_app", "ambiguous_build",
            ):
                with self.subTest(platform=platform, case=case):
                    self.check_polling(bash, script, platform, case)

    def check_polling(self, bash, script, platform, case):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            apps = [{"id": "123456"}]
            builds = [{
                "id": "build-694",
                "attributes": {
                    "version": "694", "processingState": "VALID",
                    "minOsVersion": "15.0" if platform == "IOS" else "12.0",
                },
            }]
            if case == "missing_app":
                apps = []
            elif case == "ambiguous_app":
                apps *= 2
            elif case == "ambiguous_build":
                builds *= 2
            (work / "app.json").write_text(json.dumps(apps))
            (work / "builds.json").write_text(
                "invalid json" if case == "invalid_json" else json.dumps(builds)
            )
            (work / "AuthKey.p8").write_text("test-placeholder")
            (work / "github-env").touch()
            (work / "poll.sh").write_text(MOCK_COMMANDS + script, newline="\n")
            result = subprocess.run(
                [bash, "--noprofile", "--norc", "-eo", "pipefail", "poll.sh"],
                cwd=work,
                env=dict(
                    os.environ,
                    TEST_PLATFORM=platform,
                    TEST_CASE=case,
                    GITHUB_ENV=(work / "github-env").as_posix(),
                ),
                capture_output=True, text=True, timeout=10,
            )
            output = (work / "github-env").read_text()
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
