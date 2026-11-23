"""Exercise the orchestration failure boundaries using disposable local commands."""
from contextlib import chdir, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import zlib

MODULE_PATH = Path(__file__).resolve().parents[2] / "Validation/SDK/run.py"
SPEC = importlib.util.spec_from_file_location("sdk_validation_runner", MODULE_PATH)
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="sdk-runner-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.repo = self.directory / "repo"
        self.repo.mkdir()
        self.checks = [runner.Check("probe-" + profile, profile, (self.python("print('executed')"),))
                       for profile in runner.PROFILES]
        (self.repo / "source.txt").write_text("original\n")
        subprocess.run(["git", "init", "--quiet", str(self.repo)], check=True)
        subprocess.run(["git", "add", "."], cwd=self.repo, check=True)
        subprocess.run(["git", "-c", "user.name=Runner fixture", "-c", "user.email=fixture@example.invalid",
                        "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Disposable test input"], cwd=self.repo, check=True)
        self.sha = runner.git(self.repo, "rev-parse", "HEAD").decode().strip()

    def python(self, script, **options):
        return runner.command(sys.executable, "-c", script, **options)

    def execute(self, checks, name="run"):
        output = self.directory / name
        registered = {check.id: check for check in [*self.checks, *checks]}
        with patch.object(runner, "environment", return_value={"testEnvironment": True}), redirect_stdout(io.StringIO()):
            code = runner.execute(checks, output, root=self.repo, registered=list(registered.values()))
        return code, json.loads((output / "report.json").read_text()), output

    def parse(self, kind, text, **options):
        log = self.directory / "parse.log"
        log.write_text(text)
        result = {}
        runner.inspect_log(runner.command("unused", kind=kind, **options), log, result,
                           {"output": self.directory}, time.time_ns())
        return result

    def test_nonzero_command_keeps_log_and_continues_independent_checks(self):
        checks = [runner.Check("bad", "portable", (self.python("print('failure evidence'); raise SystemExit(7)"),)), self.checks[0]]
        code, report, output = self.execute(checks)
        self.assertEqual(code, 1)
        self.assertEqual([c["status"] for c in report["checks"]], ["failed", "passed"])
        self.assertEqual(report["checks"][0]["commands"][0]["exitCode"], 7)
        self.assertIn("failure evidence", (output / "checks/bad/command-01.log").read_text())
        self.assertEqual(report["coverageReference"], "Validation/SDK/README.md")
        self.assertIn("physical-device requirements", (output / "summary.md").read_text())

    def test_missing_tool_and_wrong_platform_are_not_skipped_successfully(self):
        missing = runner.Check("missing", "portable", (runner.command("/no/such/sdk-validation-tool"),))
        wrong = runner.Check("platform", "portable", (self.python("print('must not run')"),), system="NoSuchOS")
        code, report, _ = self.execute([missing, wrong])
        self.assertEqual(code, 1)
        self.assertEqual([c["status"] for c in report["checks"]], ["unavailable", "unavailable"])

    def test_empty_selection_and_empty_commands_are_rejected(self):
        for checks in ([], [runner.Check("empty", "portable", ())]):
            with self.assertRaises(ValueError):
                runner.execute(checks, self.directory / "empty", root=self.repo)

    def test_existing_output_and_external_artifact_are_rejected(self):
        output = self.directory / "old"
        output.mkdir()
        (output / "report.json").write_text('{"status":"passed"}')
        with self.assertRaises(ValueError):
            runner.prepare_output(output)
        (output / "escape").symlink_to(self.repo / "source.txt")
        with self.assertRaises(ValueError):
            runner.artifact(output / "escape", output)

    def test_successful_exit_cannot_replace_required_artifact(self):
        check = runner.Check("artifact", "portable", (self.python("print('no artifact')"),), (("required.json", "json"),))
        code, report, _ = self.execute([check])
        self.assertEqual(code, 1)
        self.assertIn("Required artifact missing", report["checks"][0]["reason"])

    def test_source_mutation_invalidates_successful_execution(self):
        script = "from pathlib import Path; Path('source.txt').write_text('changed')"
        code, report, _ = self.execute([runner.Check("changes-source", "portable", (self.python(script),))])
        self.assertEqual(code, 1)
        self.assertEqual(report["checks"][0]["status"], "passed")
        self.assertIn("Source checkout changed during validation", report["errors"])

    def test_dirty_start_is_recorded_without_claiming_clean_acceptance(self):
        (self.repo / "source.txt").write_text("uncommitted\n")
        code, report, _ = self.execute([self.checks[0]])
        self.assertEqual(code, 0)
        self.assertTrue(report["provenance"]["dirty"])

    def test_discovery_and_xctest_zero_or_skipped_results_fail(self):
        with self.assertRaisesRegex(ValueError, "zero tests"):
            self.parse("discovery", "SwiftLangTests.SomeTests/testReal\n", pattern="MissingTests")
        for text in ("Executed 0 tests, with 0 failures\n", "Test Case '-[SwiftLangTests.Foo testA]' skipped (0.1 seconds).\n"):
            with self.assertRaises(ValueError):
                self.parse("xctest", text)

    def test_discovery_cannot_run_a_filtered_command_when_selection_is_empty(self):
        checks = [runner.Check("filtered", "portable", (
            self.python("print('SwiftLangTests.Foo/testA')", kind="discovery", pattern="Missing"),
            self.python("from pathlib import Path; Path('unwanted').write_text('ran')"),
        ))]
        code, report, _ = self.execute(checks)
        self.assertEqual(code, 1)
        self.assertEqual(len(report["checks"][0]["commands"]), 1)
        self.assertFalse((self.repo / "unwanted").exists())

    def test_xctest_counts_real_events_and_ignores_swift_testing_zero_tail(self):
        text = "Test Case '-[SwiftLangTests.SomeTests testA]' passed (0.1 seconds).\n✔ Test run with 0 tests in 0 suites passed.\n"
        parsed = self.parse("xctest", text, modules=("SwiftLangTests",))
        self.assertEqual(parsed["observed"]["executedTests"], 1)
        with self.assertRaises(ValueError):
            self.parse("xctest", text, modules=runner.MODULES)
        with self.assertRaises(ValueError):
            self.parse("xctest", text + "Test Case '-[SwiftLangTests.SomeTests testB]' failed (0.1 seconds).\n")

    def test_all_skipped_node_and_unittest_runs_cannot_pass(self):
        with self.assertRaises(ValueError):
            self.parse("node-test", "# tests 3\n# pass 0\n# fail 0\n# cancelled 0\n# skipped 3\n")
        with self.assertRaises(ValueError):
            self.parse("unittest", "Ran 3 tests in 0.1s\n\nOK (skipped=3)\n")
        self.parse("node-test", "# tests 3\n# pass 2\n# fail 0\n# cancelled 0\n# skipped 1\n")
        self.parse("unittest", "Ran 3 tests in 0.1s\n\nOK (skipped=1)\n")

    def test_gallery_requires_all_three_partitions(self):
        self.parse("gallery", "Validated 226 Gallery variants; batch=226, streamed=678, failures=0\n")
        for streamed in (0, 226, 452, 679):
            with self.assertRaises(ValueError):
                self.parse("gallery", f"Validated 226 Gallery variants; batch=226, streamed={streamed}, failures=0\n")

    def test_stale_coverage_is_not_accepted(self):
        coverage = self.directory / "old-coverage.json"
        coverage.write_text('{"type":"llvm.coverage.json.export","data":[]}')
        os.utime(coverage, (1, 1))
        with self.assertRaisesRegex(ValueError, "older"):
            self.parse("coverage", str(coverage) + "\n")

    def test_ios_summary_requires_successful_tests_for_every_product(self):
        folder = self.directory / "ios"
        folder.mkdir()
        summary = folder / "summary.json"
        check = runner.Check("ios", "ios", (self.python("pass"),), (("ios/summary.json", "ios"),))
        for data in ({}, {"status": "passed"}, {"status": "passed", "testResults": []}):
            summary.write_text(json.dumps(data))
            with self.assertRaises(ValueError):
                runner.verify_required(check, {"output": self.directory})
        data = {"status": "passed", "testResults": {"totalTestCount": 3, "passedTests": 3, "failedTests": 0, "skippedTests": 0,
                "targets": {name: {"passed": 1, "failed": 0} for name in runner.MODULES}}}
        summary.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "Gallery UI"):
            runner.verify_required(check, {"output": self.directory})
        destination = {"deviceId": "recorded-iphone", "platform": "iOS Simulator"}
        data["testResults"]["destination"] = destination
        data["uiTestResults"] = {"totalTestCount": 3, "passedTests": 3, "failedTests": 0,
            "skippedTests": 0, "expectedFailures": 0, "destination": destination,
            "targets": {"OpenUIGalleryUITests": {"passed": 3, "failed": 0}}}
        summary.write_text(json.dumps(data))
        runner.verify_required(check, {"output": self.directory})
        data["uiTestResults"]["destination"] = {"deviceId": "another-iphone", "platform": "iOS Simulator"}
        summary.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "destination"):
            runner.verify_required(check, {"output": self.directory})
        data["uiTestResults"]["destination"] = destination
        del data["testResults"]["targets"]["SwiftOpenUITests"]
        summary.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            runner.verify_required(check, {"output": self.directory})

    @unittest.skipUnless(os.name == "posix", "Process groups require POSIX")
    def test_timeout_stops_descendants_and_retains_failure(self):
        marker = self.directory / "escaped-child"
        child = f"import time; from pathlib import Path; time.sleep(0.9); Path({str(marker)!r}).write_text('escaped')"
        script = f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child!r}]); print('started',flush=True); time.sleep(30)"
        code, report, output = self.execute([runner.Check("timeout", "portable", (self.python(script, timeout=0.2),))])
        self.assertEqual(code, 1)
        self.assertEqual(report["checks"][0]["status"], "timed-out")
        time.sleep(1)
        self.assertFalse(marker.exists())
        self.assertIn("started", (output / "checks/timeout/command-01.log").read_text())

    @unittest.skipUnless(os.name == "posix", "Signals require POSIX")
    def test_sigterm_cancels_active_check_and_does_not_run_the_next(self):
        output = self.directory / "cancelled"
        script = f"""import importlib.util,sys
from pathlib import Path
s=importlib.util.spec_from_file_location('cancel_runner',{str(MODULE_PATH)!r});m=importlib.util.module_from_spec(s);sys.modules[s.name]=m;s.loader.exec_module(m)
m.environment=lambda:{{}}
checks=[m.Check('sleep','portable',(m.command(sys.executable,'-c',\"import time; print('ready',flush=True); time.sleep(30)\"),)),m.Check('later','portable',(m.command(sys.executable,'-c',\"print('later')\"),))]
sys.exit(m.execute(checks,Path({str(output)!r}),root=Path({str(self.repo)!r}),registered=checks))
"""
        process = subprocess.Popen([sys.executable, "-c", script], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            log = output / "checks/sleep/command-01.log"
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and (not log.exists() or "ready" not in log.read_text()):
                time.sleep(0.02)
            self.assertTrue(log.exists())
            process.send_signal(signal.SIGTERM)
            _, errors = process.communicate(timeout=8)
            self.assertEqual(process.returncode, 143, errors.decode())
            report = json.loads((output / "report.json").read_text())
            self.assertEqual(report["status"], "cancelled")
            self.assertEqual([c["status"] for c in report["checks"]], ["cancelled", "not-run"])
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    def prepared_collection(self):
        inputs = []
        for check in self.checks:
            code, _, output = self.execute([check], check.profile)
            self.assertEqual(code, 0)
            inputs.append(output)
        return inputs

    def collection(self, inputs, name="collection", sha=None):
        output = self.directory / name
        code = runner.collect(inputs, output, sha or self.sha, checks=self.checks)
        return code, json.loads((output / "report.json").read_text())

    def test_collect_requires_all_profiles_and_unique_complete_checks(self):
        inputs = self.prepared_collection()
        code, report = self.collection(inputs)
        self.assertEqual(code, 0, report["errors"])
        self.assertEqual(len(report["checks"]), 4)
        self.assertEqual(self.collection(inputs[:-1], "missing")[0], 1)
        self.assertEqual(self.collection(inputs + inputs[:1], "duplicate")[0], 1)
        self.assertEqual(self.collection(inputs, "wrong-sha", "0" * 40)[0], 1)

    def test_collect_relative_cli_inputs_retain_required_visual_evidence(self):
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
               + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00\xff")) + chunk(b"IEND", b""))
        first = self.checks[0]
        script = ("from pathlib import Path; p=Path('{visual}')/'gallery-editorial'; p.mkdir(parents=True); "
                  f"(p/'openui-fixture.png').write_bytes({png!r}); "
                  "(p/'openui-fixture.json').write_text('{\"fixture\":true}')")
        self.checks[0] = runner.Check(first.id, first.profile, (self.python(script),), (
            ("{visual}/gallery-editorial/openui-*.png", "file"),
            ("{visual}/gallery-editorial/openui-*.json", "json"),
        ))
        inputs = self.prepared_collection()
        arguments = ["collect", "--expected-sha", self.sha, "--output", "relative-collection"]
        for path in inputs:
            arguments.extend(["--input", path.relative_to(self.directory).as_posix()])
        with chdir(self.directory), patch.object(runner, "registry", return_value=self.checks):
            code = runner.main(arguments)
        report = json.loads((self.directory / "relative-collection/report.json").read_text())
        self.assertEqual(code, 0, report["errors"])
        artifacts = report["checks"][0]["artifacts"]
        self.assertTrue(any(item["path"].endswith("openui-fixture.png") for item in artifacts))
        image = inputs[0] / "visual" / first.id / "gallery-editorial/openui-fixture.png"
        image.write_bytes(png + b"tampered")
        arguments[arguments.index("--output") + 1] = "relative-tampered"
        with chdir(self.directory), patch.object(runner, "registry", return_value=self.checks):
            self.assertEqual(runner.main(arguments), 1)
        tampered = json.loads((self.directory / "relative-tampered/report.json").read_text())
        self.assertTrue(any("Artifact size/hash mismatch" in error for error in tampered["errors"]))

    def test_collect_rejects_modified_or_missing_artifacts(self):
        inputs = self.prepared_collection()
        log = inputs[0] / "checks" / self.checks[0].id / "command-01.log"
        log.write_text("tampered")
        self.assertEqual(self.collection(inputs, "tampered")[0], 1)
        log.unlink()
        self.assertEqual(self.collection(inputs, "missing-log")[0], 1)

    def test_collect_rejects_dirty_unfinished_or_unexecuted_reports(self):
        inputs = self.prepared_collection()
        path = inputs[0] / "report.json"
        original = json.loads(path.read_text())
        for label, mutate in (
            ("dirty", lambda data: data["provenance"].update(dirty=True)),
            ("unfinished", lambda data: data.update(status="running")),
            ("not-run", lambda data: data["checks"][0].update(status="not-run")),
            ("zero-commands", lambda data: data["checks"][0].update(commands=[])),
        ):
            data = json.loads(json.dumps(original))
            mutate(data)
            path.write_text(json.dumps(data))
            self.assertEqual(self.collection(inputs, label)[0], 1, label)

    def test_partial_selection_cannot_claim_unselected_profile_checks(self):
        code, report, output = self.execute([self.checks[0]])
        self.assertEqual(code, 0)
        self.assertEqual(report["unselectedChecks"], [check.id for check in self.checks[1:]])
        self.assertEqual([profile["status"] for profile in report["profiles"]],
                         ["passed", "not-selected", "not-selected", "not-selected"])
        for check in self.checks[1:]:
            self.assertIn(check.id, (output / "summary.md").read_text())
        self.assertNotIn("cases", report)
        self.assertNotIn("matrixSHA256", report)

    def test_measurement_artifacts_cannot_be_empty_identity_only_reports(self):
        output = self.directory / "measurements"
        output.mkdir()
        artifact = output / "result.json"
        for kind, payload in (("coverage", {"type": "llvm.coverage.json.export", "data": []}),
                              ("performance", {"workload": "language-runtime", "configuration": "release"})):
            artifact.write_text(json.dumps(payload))
            check = runner.Check("measurement", "macos", (), (("result.json", kind),))
            with self.assertRaises(ValueError, msg=kind):
                runner.verify_required(check, {"output": output})

    def test_report_replace_failure_leaves_the_previous_checkpoint(self):
        path = self.directory / "checkpoint.json"
        path.write_text('{"status":"running"}')
        with patch.object(runner.os, "replace", side_effect=OSError("write failure")):
            with self.assertRaises(OSError):
                runner.atomic_write(path, '{"status":"passed"}')
        self.assertEqual(json.loads(path.read_text())["status"], "running")


if __name__ == "__main__":
    unittest.main()
