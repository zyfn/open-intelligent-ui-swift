#!/usr/bin/env python3
"""Run the existing package tests on an installed iPhone Simulator.

The package's automatic Xcode scheme is authoritative. Build-only success,
empty test results and missing product test bundles cannot pass this check.
Raw Xcode results are retained alongside the small machine-readable summary.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from uuid import UUID


ROOT = Path(__file__).resolve().parents[2]
SCHEME = "openui-swift-sdk-Package"
TARGETS = ("SwiftLangTests", "SwiftOpenUITests", "SwiftIntelligentUITests")
RESULT_BUCKETS = {"Passed": "passed", "Failed": "failed", "Skipped": "skipped",
                  "Expected Failure": "expectedFailures"}


def choose_device(inventory: dict, requested: str | None = None) -> dict:
    if not isinstance(inventory, dict) or not isinstance(inventory.get("devices"), dict):
        raise ValueError("Invalid Simulator device inventory")
    candidates = []
    for runtime, devices in inventory["devices"].items():
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+(?:-\d+)*)", runtime)
        if not match:
            continue
        version = tuple(int(part) for part in match[1].split("-"))
        if version[0] < 16:
            continue
        if not isinstance(devices, list):
            raise ValueError(f"Invalid device list for {runtime}")
        for device in devices:
            if not isinstance(device, dict):
                raise ValueError(f"Invalid Simulator device in {runtime}")
            name = device.get("name")
            device_type = device.get("deviceTypeIdentifier")
            is_phone = (device_type.startswith("com.apple.CoreSimulator.SimDeviceType.iPhone-")
                        if isinstance(device_type, str) else isinstance(name, str) and name.startswith("iPhone"))
            if device.get("isAvailable") is not True or not is_phone or not isinstance(name, str):
                continue
            udid = device.get("udid")
            if not isinstance(udid, str):
                raise ValueError(f"Available iPhone Simulator has no UDID: {name}")
            try:
                UUID(udid)
            except ValueError as error:
                raise ValueError(f"Invalid Simulator UDID: {udid}") from error
            if requested and udid.casefold() != requested.casefold():
                continue
            candidates.append((version, device.get("state") == "Booted", name,
                               {**device, "runtime": runtime}))
    if not candidates:
        raise ValueError("No matching available iPhone Simulator; no build-only fallback")
    # The actual runtime and UDID are recorded; never infer a device from an SDK.
    candidates.sort(key=lambda item: (item[0], item[1], item[2]), reverse=True)
    return candidates[0][3]


def validate_results(summary: dict, tree: dict, selected_device: dict) -> dict:
    """Validate xcresulttool's modern test-results JSON, failing closed."""
    if not isinstance(summary, dict) or not isinstance(tree, dict):
        raise ValueError("Invalid xcresult summary or test tree")
    counts = {}
    for field in ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures"):
        value = summary.get(field)
        if type(value) is not int or value < 0:
            raise ValueError(f"Missing/invalid xcresult summary field: {field}")
        counts[field] = value
    if summary.get("result") != "Passed" or counts["failedTests"] or counts["passedTests"] == 0:
        raise ValueError(f"iOS tests did not pass with nonzero executions: {counts}")
    if counts["totalTestCount"] != sum(counts[field] for field in
                                      ("passedTests", "failedTests", "skippedTests", "expectedFailures")):
        raise ValueError("xcresult summary has inconsistent test counts")
    devices = tree.get("devices")
    if not isinstance(devices, list) or len(devices) != 1 or not isinstance(devices[0], dict):
        raise ValueError("Expected results from exactly the selected iPhone Simulator")
    destination = devices[0]
    if any(not isinstance(destination.get(key), str) or not destination[key]
           for key in ("deviceId", "modelName", "platform", "osVersion")):
        raise ValueError("xcresult is missing actual destination identity")
    if destination["platform"] != "iOS Simulator" or not destination["modelName"].startswith("iPhone"):
        raise ValueError(f"Tests did not execute on an iPhone Simulator: {destination}")
    if destination["deviceId"].casefold() != selected_device["udid"].casefold():
        raise ValueError("xcresult destination differs from the selected Simulator UDID")
    version = destination["osVersion"]
    expected_version = selected_device["runtime"].rsplit(".iOS-", 1)[-1].replace("-", ".")
    if not re.fullmatch(r"\d+(?:\.\d+)*", version) or int(version.split(".")[0]) < 16:
        raise ValueError(f"Unsupported executed iOS runtime: {version}")
    # A runtime reported as 26.3 is the same version as 26.3.0, while a
    # silently substituted runtime must never satisfy the recorded selection.
    normalize = lambda value: tuple(int(part) for part in value.split(".")) + (0,) * (4 - len(value.split(".")))
    if normalize(version) != normalize(expected_version):
        raise ValueError(f"Executed iOS runtime {version} differs from {expected_version}")
    nodes = tree.get("testNodes")
    if not isinstance(nodes, list) or not nodes:
        raise ValueError("xcresult contains no testNodes")
    bundles: dict[str, dict] = {}
    identifiers: dict[str, set[str]] = {}

    def visit(node: dict, target: str | None = None) -> None:
        if not isinstance(node, dict):
            raise ValueError("Invalid xcresult test node")
        node_type = node.get("nodeType")
        if not isinstance(node_type, str) or not node_type:
            raise ValueError("xcresult node is missing its type")
        children = node.get("children", [])
        if not isinstance(children, list):
            raise ValueError(f"Invalid children for xcresult node: {node.get('name')}")
        outcome = node.get("result")
        if outcome is not None and (not isinstance(outcome, str) or outcome not in RESULT_BUCKETS):
            raise ValueError(f"Unknown test result: {node.get('name')}: {outcome}")
        if outcome == "Failed":
            raise ValueError(f"Failed native test node: {node.get('name')}")
        if node_type in ("Unit test bundle", "UI test bundle"):
            name = node.get("name")
            if not isinstance(name, str) or not name:
                raise ValueError("xcresult test bundle has no name")
            target = name.removesuffix(".xctest")
            if target in bundles:
                raise ValueError(f"Duplicate product test bundle: {target}")
            if target in TARGETS and (node_type != "Unit test bundle" or outcome in ("Skipped", "Expected Failure")):
                raise ValueError(f"Required unit test bundle was not executed successfully: {target}")
            bundles[target] = {"passed": 0, "failed": 0, "skipped": 0,
                               "expectedFailures": 0, "tests": []}
            identifiers[target] = set()
        if node_type == "Test Case":
            if target not in bundles:
                raise ValueError("xcresult test case is not associated with a test bundle")
            result = node.get("result")
            key = RESULT_BUCKETS.get(result)
            if key is None:
                raise ValueError(f"Unknown test result: {node.get('name')}: {result}")
            identifier = node.get("nodeIdentifier") or node.get("nodeIdentifierURL")
            if not isinstance(identifier, str) or not identifier.strip():
                raise ValueError(f"Executed test has no identifier: {target}: {node.get('name')}")
            if identifier in identifiers[target]:
                raise ValueError(f"Duplicate test case: {target}/{identifier}")
            identifiers[target].add(identifier)
            bundles[target][key] += 1
            bundles[target]["tests"].append({"name": node.get("name"),
                                             "identifier": identifier,
                                             "result": result})
            # Inspect run outcomes, including a failed attempt followed by a
            # retry, but do not count Device/Repetition/Run nodes as more tests.
            def inspect_runs(child: dict) -> None:
                if not isinstance(child, dict):
                    raise ValueError("Invalid xcresult test execution node")
                status = child.get("result")
                if status is not None and (not isinstance(status, str) or status not in RESULT_BUCKETS):
                    raise ValueError(f"Unknown test execution result: {identifier}: {status}")
                if status == "Failed":
                    raise ValueError(f"Failed test execution, including a retried attempt: {identifier}")
                nested = child.get("children", [])
                if not isinstance(nested, list):
                    raise ValueError(f"Invalid test execution children: {identifier}")
                for descendant in nested:
                    inspect_runs(descendant)
            for child in children:
                inspect_runs(child)
            return
        for child in children:
            visit(child, target)

    for node in nodes:
        visit(node)
    for target in TARGETS:
        result = bundles.get(target)
        if result is None or result["passed"] == 0 or result["failed"]:
            raise ValueError(f"No successful executed tests for {target}: {result}")
    for field, bucket in (("passedTests", "passed"), ("failedTests", "failed"),
                          ("skippedTests", "skipped"), ("expectedFailures", "expectedFailures")):
        observed = sum(bundle[bucket] for bundle in bundles.values())
        if observed != counts[field]:
            raise ValueError(f"xcresult summary/tree disagree for {field}: {counts[field]} versus {observed}")
    return {**counts, "targets": bundles, "destination": destination}


class IOSRun:
    def __init__(self, output: Path):
        self.output = output
        self.report = {"schemaVersion": 1, "status": "running", "scheme": SCHEME,
                       "startedAt": datetime.now(timezone.utc).isoformat(),
                       "commands": [], "failures": []}
        self.process: subprocess.Popen | None = None
        self.save()

    def save(self) -> None:
        temporary = self.output / "summary.json.tmp"
        temporary.write_text(json.dumps(self.report, ensure_ascii=False, indent=2) + "\n")
        temporary.replace(self.output / "summary.json")

    def command(self, name: str, argv: list[str], timeout: int = 900) -> Path:
        log = self.output / f"{name}.log"
        record = {"id": name, "argv": argv, "log": log.name, "timeoutSeconds": timeout}
        self.report["commands"].append(record)
        self.save()
        print(f"[ios] {name}", flush=True)
        started = time.monotonic()
        try:
            with log.open("wb") as stream:
                self.process = subprocess.Popen(argv, cwd=ROOT, stdout=stream,
                                                stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = self.process.wait(timeout=timeout)
                except (subprocess.TimeoutExpired, KeyboardInterrupt):
                    os.killpg(self.process.pid, signal.SIGTERM)
                    try:
                        self.process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(self.process.pid, signal.SIGKILL)
                        self.process.wait()
                    raise
            record["exitCode"] = code
            if code:
                print(log.read_text(errors="replace")[-8000:], flush=True)
                raise RuntimeError(f"{name} exited {code}; see {log.name}")
            return log
        except (Exception, KeyboardInterrupt) as error:
            record["error"] = str(error) or "Interrupted"
            if self.process is not None and self.process.poll() is not None:
                record["exitCode"] = self.process.returncode
            raise
        finally:
            self.process = None
            record["durationSeconds"] = round(time.monotonic() - started, 3)
            self.save()

    def json_command(self, name: str, argv: list[str], timeout: int = 900) -> dict:
        log = self.command(name, argv, timeout)
        raw = log.read_text()
        # xcodebuild -list may put package-resolution notices before its JSON.
        value = None
        decoder = json.JSONDecoder()
        for match in re.finditer(r"(?m)^\s*\{", raw):
            try:
                suffix = raw[match.start():].lstrip()
                candidate, end = decoder.raw_decode(suffix)
                if isinstance(candidate, dict) and not suffix[end:].strip():
                    value = candidate
                    break
            except json.JSONDecodeError:
                continue
        if value is None:
            raise ValueError(f"{name} produced no JSON object")
        (self.output / f"{name}.json").write_text(json.dumps(value, indent=2) + "\n")
        return value

    def tests(self, scratch: Path, requested_device: str | None) -> None:
        listing = self.json_command("schemes", ["xcodebuild", "-list", "-json"])
        schemes = [scheme for section in ("workspace", "project")
                   for scheme in listing.get(section, {}).get("schemes", [])]
        if SCHEME not in schemes:
            raise ValueError(f"Expected package scheme {SCHEME}; discovered {schemes}")
        inventory = self.json_command("devices", ["xcrun", "simctl", "list", "devices", "available", "--json"])
        device = choose_device(inventory, requested_device)
        self.report["device"] = device
        self.save()
        if device.get("state") != "Booted":
            self.command("boot", ["xcrun", "simctl", "boot", device["udid"]], 180)
        self.command("boot-status", ["xcrun", "simctl", "bootstatus", device["udid"], "-b"], 300)
        bundle = self.output / "sdk-tests.xcresult"
        test_error = None
        try:
            self.command("sdk-tests", ["xcodebuild", "test", "-scheme", SCHEME,
                "-destination", f"platform=iOS Simulator,id={device['udid']}",
                "-destination-timeout", "120", "-derivedDataPath", str(scratch / "tests"),
                "-resultBundlePath", str(bundle), "-parallel-testing-enabled", "NO",
                "-enableCodeCoverage", "YES", "CODE_SIGNING_ALLOWED=NO"], 2700)
        except Exception as error:
            test_error = error
        # Preserve results even when XCTest fails; a failed command stays failed.
        try:
            for kind in ("summary", "tests"):
                self.command(f"xcresult-{kind}-help", ["xcrun", "xcresulttool", "help", "get", "test-results", kind], 60)
                self.command(f"xcresult-{kind}-schema", ["xcrun", "xcresulttool", "get", "test-results", kind, "--schema"], 60)
            summary = self.json_command("test-summary", ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle)], 120)
            tree = self.json_command("test-tree", ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle)], 120)
            self.report["testResults"] = validate_results(summary, tree, device)
            coverage = self.json_command("coverage", ["xcrun", "xccov", "view", "--report", "--json", str(bundle)], 180)
            if not isinstance(coverage.get("targets"), list) or not coverage["targets"]:
                raise ValueError("No measured iOS code coverage targets")
        except Exception as error:
            if test_error:
                self.report["failures"].append(str(error))
            else:
                raise
        finally:
            if test_error:
                raise test_error

    def builds(self, scratch: Path) -> None:
        sdk = self.command("simulator-sdk", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], 60).read_text().strip()
        if not Path(sdk).is_dir():
            raise ValueError(f"Simulator SDK path does not exist: {sdk}")
        for target in ("SwiftOpenUI", "SwiftIntelligentUI"):
            try:
                self.command(f"{target}-ios16", ["swift", "build", "--target", target,
                    "--scratch-path", str(scratch / "minimum-deployment"),
                    "--triple", "arm64-apple-ios16.0-simulator", "--sdk", sdk], 900)
            except Exception as error:
                self.report["failures"].append(str(error))
        self.command("gallery-build", ["xcodebuild", "-project", "Examples/Gallery/OpenUIGallery.xcodeproj",
            "-scheme", "OpenUIGallery", "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", str(scratch / "gallery"), "CODE_SIGNING_ALLOWED=NO", "build"], 900)


def main() -> int:
    def interrupt(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupt)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--device-id", help="Use this available iPhone Simulator UDID")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("--output must be new or empty; old evidence cannot satisfy this run")
    output.mkdir(parents=True, exist_ok=True)
    run = IOSRun(output)
    try:
        if platform.system() != "Darwin":
            raise RuntimeError("iOS execution requires macOS and Xcode")
        with tempfile.TemporaryDirectory(prefix="openui-ios-") as temporary:
            scratch = Path(temporary)
            for action in (lambda: run.tests(scratch, args.device_id), lambda: run.builds(scratch)):
                try:
                    action()
                except Exception as error:
                    run.report["failures"].append(str(error))
                    run.save()
    except (Exception, KeyboardInterrupt) as error:
        run.report["failures"].append(str(error) or "Interrupted")
    finally:
        if not run.report.get("testResults"):
            run.report["failures"].append("No validated iOS test execution evidence")
        run.report["status"] = "failed" if run.report["failures"] else "passed"
        run.report["finishedAt"] = datetime.now(timezone.utc).isoformat()
        run.save()
    print(json.dumps({"status": run.report["status"], "failures": run.report["failures"]}))
    return 0 if run.report["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
