"""Negative evidence tests for the iOS runner; these never execute XCTest."""

from copy import deepcopy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

_runner_path = Path(__file__).resolve().parents[2] / "Validation" / "SDK" / "ios.py"
_runner_spec = importlib.util.spec_from_file_location("sdk_ios_validation", _runner_path)
assert _runner_spec is not None and _runner_spec.loader is not None
ios = importlib.util.module_from_spec(_runner_spec)
_runner_spec.loader.exec_module(ios)


DEVICE_ID = "00000000-0000-4000-8000-000000000001"
SECOND_DEVICE_ID = "00000000-0000-4000-8000-000000000002"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-3"


def device(**changes):
    return {"udid": DEVICE_ID, "name": "iPhone 16", "isAvailable": True,
            "state": "Booted", "runtime": RUNTIME,
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16", **changes}


def case(identifier="ContractTests/testPublicEntry()", result="Passed"):
    return {"name": identifier.split("/")[-1], "nodeIdentifier": identifier,
            "nodeType": "Test Case", "result": result}


def results():
    # This is the documented modern tree shape: plan -> bundle -> suite ->
    # case. It represents synthetic verifier input, not native test evidence.
    bundles = [
        {"name": target, "nodeType": "Unit test bundle", "result": "Passed",
         "children": [{"name": "ContractTests", "nodeType": "Test Suite",
                       "result": "Passed", "children": [case()]}]}
        for target in ios.TARGETS
    ]
    tree = {"devices": [{"deviceId": DEVICE_ID, "modelName": "iPhone 16",
                         "osVersion": "26.3", "platform": "iOS Simulator"}],
            "testNodes": [{"name": "SDK", "nodeType": "Test Plan", "result": "Passed",
                           "children": bundles}]}
    summary = {"result": "Passed", "totalTestCount": 3, "passedTests": 3,
               "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
    return summary, tree


def bundles(tree):
    return tree["testNodes"][0]["children"]


def cases(tree, index=0):
    return bundles(tree)[index]["children"][0]["children"]


class ResultEvidenceTests(unittest.TestCase):
    def test_all_three_products_require_executed_cases(self):
        summary, tree = results()
        report = ios.validate_results(summary, tree, device())
        self.assertEqual(set(report["targets"]), set(ios.TARGETS))
        self.assertEqual([report["targets"][target]["passed"] for target in ios.TARGETS], [1, 1, 1])
        self.assertEqual(report["destination"]["deviceId"], DEVICE_ID)

    def test_build_only_or_empty_results_are_rejected(self):
        for kind in ("zero-counts", "empty-tree", "missing-tree", "empty-bundles"):
            with self.subTest(kind=kind):
                summary, tree = results()
                if kind == "zero-counts":
                    summary.update(totalTestCount=0, passedTests=0)
                elif kind == "empty-tree":
                    tree["testNodes"] = []
                elif kind == "missing-tree":
                    del tree["testNodes"]
                else:
                    for bundle in bundles(tree):
                        bundle["children"] = []
                with self.assertRaises(ValueError):
                    ios.validate_results(summary, tree, device())

    def test_missing_product_is_not_hidden_by_valid_total_counts(self):
        summary, tree = results()
        bundles(tree).pop()
        summary.update(totalTestCount=2, passedTests=2)
        with self.assertRaisesRegex(ValueError, "SwiftIntelligentUITests"):
            ios.validate_results(summary, tree, device())

    def test_a_product_with_only_skipped_tests_cannot_pass(self):
        summary, tree = results()
        cases(tree)[0]["result"] = "Skipped"
        summary.update(passedTests=2, skippedTests=1)
        with self.assertRaisesRegex(ValueError, "SwiftLangTests"):
            ios.validate_results(summary, tree, device())

    def test_skips_are_retained_separately_from_successful_executions(self):
        summary, tree = results()
        cases(tree).append(case("ContractTests/testUnavailableFeature()", "Skipped"))
        summary.update(totalTestCount=4, skippedTests=1)
        report = ios.validate_results(summary, tree, device())
        self.assertEqual(report["passedTests"], 3)
        self.assertEqual(report["skippedTests"], 1)
        self.assertEqual(report["targets"]["SwiftLangTests"]["passed"], 1)
        self.assertEqual(report["targets"]["SwiftLangTests"]["skipped"], 1)

    def test_failed_or_unknown_results_cannot_be_hidden_by_a_passed_summary(self):
        for result in ("Failed", "unknown", "Not Run", None, {}, ""):
            with self.subTest(result=result):
                summary, tree = results()
                cases(tree)[0]["result"] = result
                with self.assertRaises(ValueError):
                    ios.validate_results(summary, tree, device())
        for result in ("Failed", "Skipped", "unknown", None):
            with self.subTest(summary=result):
                summary, tree = results()
                summary["result"] = result
                with self.assertRaises(ValueError):
                    ios.validate_results(summary, tree, device())

    def test_summary_counts_must_be_typed_and_match_the_case_tree(self):
        for changes in ({"totalTestCount": 4}, {"passedTests": True}, {"failedTests": -1},
                        {"totalTestCount": 4, "passedTests": 4}, {"skippedTests": "0"}):
            with self.subTest(changes=changes):
                summary, tree = results()
                summary.update(changes)
                with self.assertRaises(ValueError):
                    ios.validate_results(summary, tree, device())
        summary, tree = results()
        del summary["expectedFailures"]
        with self.assertRaises(ValueError):
            ios.validate_results(summary, tree, device())

    def test_duplicate_bundles_or_case_ids_are_rejected(self):
        summary, tree = results()
        bundles(tree).append(deepcopy(bundles(tree)[0]))
        summary.update(totalTestCount=4, passedTests=4)
        with self.assertRaisesRegex(ValueError, "Duplicate product test bundle"):
            ios.validate_results(summary, tree, device())
        summary, tree = results()
        cases(tree).append(deepcopy(cases(tree)[0]))
        summary.update(totalTestCount=4, passedTests=4)
        with self.assertRaisesRegex(ValueError, "Duplicate test case"):
            ios.validate_results(summary, tree, device())

    def test_execution_details_do_not_inflate_case_counts_or_hide_retried_failures(self):
        summary, tree = results()
        cases(tree)[0]["children"] = [
            {"name": "iPhone 16", "nodeType": "Device", "result": "Passed", "children": [
                {"name": "Run", "nodeType": "Test Case Run", "result": "Passed"}]}]
        self.assertEqual(ios.validate_results(summary, tree, device())["totalTestCount"], 3)
        cases(tree)[0]["children"].append(
            {"name": "First Run", "nodeType": "Repetition", "result": "Failed"})
        with self.assertRaisesRegex(ValueError, "retried attempt"):
            ios.validate_results(summary, tree, device())

    def test_unidentified_or_malformed_cases_cannot_supply_execution_evidence(self):
        for change in ("identifier", "children", "nodeType"):
            with self.subTest(change=change):
                summary, tree = results()
                if change == "identifier":
                    del cases(tree)[0]["nodeIdentifier"]
                elif change == "children":
                    cases(tree)[0]["children"] = {}
                else:
                    del cases(tree)[0]["nodeType"]
                with self.assertRaises(ValueError):
                    ios.validate_results(summary, tree, device())

    def test_actual_result_device_must_match_the_selected_supported_iphone(self):
        for changes in ({"deviceId": SECOND_DEVICE_ID}, {"modelName": "iPad Pro"},
                        {"platform": "iOS"}, {"osVersion": "15.5"},
                        {"osVersion": "26.4"}, {"osVersion": "unknown"}):
            with self.subTest(changes=changes):
                summary, tree = results()
                tree["devices"][0].update(changes)
                with self.assertRaises(ValueError):
                    ios.validate_results(summary, tree, device())
        for devices in (None, [], [results()[1]["devices"][0]] * 2):
            with self.subTest(devices=devices):
                summary, tree = results()
                tree["devices"] = devices
                with self.assertRaises(ValueError):
                    ios.validate_results(summary, tree, device())


class DeviceSelectionTests(unittest.TestCase):
    def test_newest_available_runtime_and_requested_device_are_explicit(self):
        inventory = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-4": [device(udid=SECOND_DEVICE_ID)],
            RUNTIME: [device(state="Shutdown")],
        }}
        self.assertEqual(ios.choose_device(inventory)["udid"], DEVICE_ID)
        selected = ios.choose_device(inventory, SECOND_DEVICE_ID)
        self.assertEqual(selected["runtime"], "com.apple.CoreSimulator.SimRuntime.iOS-18-4")

    def test_unavailable_wrong_platform_or_below_minimum_devices_are_rejected(self):
        entries = [
            (RUNTIME, device(isAvailable=False)),
            (RUNTIME, device(isAvailable="false")),
            (RUNTIME, device(deviceTypeIdentifier="com.apple.CoreSimulator.SimDeviceType.iPad-Pro")),
            ("com.apple.CoreSimulator.SimRuntime.tvOS-26-3", device()),
            ("com.apple.CoreSimulator.SimRuntime.iOS-15-5", device()),
            (RUNTIME, device(udid="not-a-device-id")),
        ]
        for runtime, entry in entries:
            with self.subTest(runtime=runtime, entry=entry):
                with self.assertRaises(ValueError):
                    ios.choose_device({"devices": {runtime: [entry]}})

    def test_missing_requested_device_does_not_fall_back(self):
        with self.assertRaises(ValueError):
            ios.choose_device({"devices": {RUNTIME: [device()]}}, SECOND_DEVICE_ID)

    def test_renamed_phone_uses_device_type_not_its_display_name(self):
        selected = ios.choose_device({"devices": {RUNTIME: [device(name="SDK test destination")]}})
        self.assertEqual(selected["udid"], DEVICE_ID)


class RunnerEvidenceTests(unittest.TestCase):
    def test_interruption_terminates_the_child_group_and_records_its_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            run = ios.IOSRun(Path(directory))
            child = Mock(pid=12345, returncode=-ios.signal.SIGTERM)
            child.wait.side_effect = [KeyboardInterrupt(), -ios.signal.SIGTERM]
            child.poll.return_value = -ios.signal.SIGTERM
            with patch.object(ios.subprocess, "Popen", return_value=child), \
                 patch.object(ios.os, "killpg") as kill_group, patch("sys.stdout", new_callable=io.StringIO):
                with self.assertRaises(KeyboardInterrupt):
                    run.command("interrupted-test", ["xcodebuild", "test"])
            kill_group.assert_called_once_with(child.pid, ios.signal.SIGTERM)
            record = json.loads((Path(directory) / "summary.json").read_text())["commands"][0]
            self.assertEqual(record["error"], "Interrupted")
            self.assertEqual(record["exitCode"], -ios.signal.SIGTERM)
            self.assertIsNone(run.process)

    def test_json_command_retains_outer_object_after_package_resolution_notices(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            run = ios.IOSRun(output)
            log = output / "listing.log"
            expected = {"workspace": {"name": "SDK", "schemes": [ios.SCHEME]}}
            log.write_text("Resolve Package Graph\n" + json.dumps(expected, indent=2) + "\n")
            with patch.object(run, "command", return_value=log):
                self.assertEqual(run.json_command("schemes", []), expected)

    def test_failed_xcode_command_remains_failed_even_if_a_bundle_claims_success(self):
        with tempfile.TemporaryDirectory() as directory:
            run = ios.IOSRun(Path(directory))
            summary, tree = results()
            data = {"schemes": {"workspace": {"schemes": [ios.SCHEME]}},
                    "devices": {"devices": {RUNTIME: [device()]}},
                    "test-summary": summary, "test-tree": tree, "coverage": {"targets": [{}]}}
            def command(name, *args):
                if name == "sdk-tests":
                    raise RuntimeError("xcodebuild exited 65")
                return Path(directory) / (name + ".log")
            with patch.object(run, "command", side_effect=command), \
                 patch.object(run, "json_command", side_effect=lambda name, *args: data[name]):
                with self.assertRaisesRegex(RuntimeError, "exited 65"):
                    run.tests(Path(directory), None)

    def test_a_stage_without_validated_test_results_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "evidence"
            with patch("sys.argv", ["ios.py", "--output", str(output)]), \
                 patch("sys.stdout", new_callable=io.StringIO), \
                 patch.object(ios.signal, "signal"), patch.object(ios.platform, "system", return_value="Darwin"), \
                 patch.object(ios.IOSRun, "tests"), patch.object(ios.IOSRun, "builds"):
                self.assertEqual(ios.main(), 1)
            report = json.loads((output / "summary.json").read_text())
            self.assertEqual(report["status"], "failed")
            self.assertIn("No validated iOS test execution evidence", report["failures"])

    def test_interrupted_stage_finishes_with_failed_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "evidence"
            with patch("sys.argv", ["ios.py", "--output", str(output)]), \
                 patch("sys.stdout", new_callable=io.StringIO), \
                 patch.object(ios.signal, "signal"), patch.object(ios.platform, "system", return_value="Darwin"), \
                 patch.object(ios.IOSRun, "tests", side_effect=KeyboardInterrupt()), \
                 patch.object(ios.IOSRun, "builds") as build:
                self.assertEqual(ios.main(), 1)
            build.assert_not_called()
            report = json.loads((output / "summary.json").read_text())
            self.assertEqual(report["status"], "failed")
            self.assertIn("Interrupted", report["failures"])


if __name__ == "__main__":
    unittest.main()
