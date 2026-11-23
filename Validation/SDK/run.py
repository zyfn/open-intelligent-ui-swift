#!/usr/bin/env python3
"""Run existing SDK tests and tools, retaining their execution evidence."""
from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from datetime import datetime, timezone
import glob
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
PROFILES = ("portable", "security", "macos", "ios")
MODULES = ("SwiftLangTests", "SwiftOpenUITests", "SwiftIntelligentUITests")
DEBUG_FILTER = (
    "QueryDispatchBoundaryTests|NativeValueBudgetTests|MutationRetirementTests|NativeProjectionInputBudgetTests"
    "|ResourceCacheBudgetTests|ResourceStoreTests|SharedCoreBridgeTests|SliderFeedbackRenderingTests"
    "|testInterruptedSVGWithAnUnclosedSourceReplacesLoadingWithReadableFallback"
    "|testMountedStoreReadersLeaveUnrelatedSiblingBuildersAndBodiesAlone"
    "|testRefetchDuringFlightQueuesAndRefreshTimerStops|SemanticTypographyTests"
)
COMPOSITION_FILTER = r"SwiftIntelligentUITests\.(LayoutTests|SVGLayoutTests|ProductCardTests|SliderTests|GenerationContractTests|ComponentSelectionTests)/"
RELEASE_FILTER = (
    "NativeImageSizingTests|NativeMediaRetryTests|NativeMediaResourceTests|SignedMediaResourceTests|ResourceStoreTests"
    "|StreamingTextPresentationTests|MountedStreamingTextProgressTests|StreamingMediaRetentionTests"
    "|AdaptivePresentationTests|PhotoCardGeometryTests|ReadingControlPresentationTests|ObjectCardCompositionTests"
    "|StreamingLayoutContractTests|LayoutMeasurementReductionTests|ButtonLayoutContractTests|ChartInspectionTests"
    "|NativeComponentsTests|BoundaryIdentityTests|NativeComponentSubscriptionTests|StreamingRenderIsolationTests"
    "|TableAppearanceTests|ReadingRhythmTests|StreamingVisualStateTests|TableMountedViewTests|ComponentLibraryTests"
    "|ComponentReadinessTests|FullLibraryParityTests|NativeActionRenderingTests|LibraryFacadeTests|InputTests"
    "|AncestorInteractionScopeTests|SliderFeedbackRenderingTests|StreamingFormCorrectnessTests|ComponentRenderInputTests"
    "|NativePresentationCommitTests|NativeLiveElementUpdateTests|QueryDispatchBoundaryTests|NativeValueBudgetTests"
    "|MutationRetirementTests|NativeProjectionInputBudgetTests|ActionWorkBudgetTests|RuntimeReentrancyTests"
    "|MCPInputBudgetTests|StoreAggregateBudgetTests|NativeContextBudgetTests|RuntimeLimitsTests|ResourceCacheBudgetTests"
    "|SharedCoreBridgeTests|FramedStreamingTests|ProjectionBridgeTests|SourceSnapshotBridgeTests"
    "|EvaluationDefinitionsTests|StreamingPublicationTests|LiveElementIndexTests|FieldSelectionRenderingTests"
    "|" + COMPOSITION_FILTER + "|testRefetchDuringFlightQueuesAndRefreshTimerStops|SemanticTypographyTests"
)
OBSOLETE_IMPORT_CHECK = r"""from pathlib import Path
import re, sys
pattern = re.compile(r'(^|\s)(@testable\s+)?import\s+(OpenUILang|OpenUI|OpenIntelligentUI|OpenUICore|OpenSwiftUI|OpenIntelligentSwiftUI|OpenUISwiftUI)(\s|$)', re.M)
hits = [str(p) for directory in ['Sources','Tests','Examples','Tools'] for p in Path(directory).rglob('*.swift') if pattern.search(p.read_text(errors='replace'))]
print('\n'.join(hits) if hits else 'No obsolete Swift module imports')
sys.exit(bool(hits))
"""


@dataclass(frozen=True)
class Command:
    argv: tuple[str, ...]
    kind: str = "process"
    timeout: float = 600
    pattern: str | None = None
    modules: tuple[str, ...] = ()
    env: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class Check:
    id: str
    profile: str
    commands: tuple[Command, ...]
    required: tuple[tuple[str, str], ...] = ()
    system: str | None = None


def command(*argv, **options):
    return Command(tuple(argv), **options)


def filtered_tests(pattern, *, configuration="debug", extra=(), modules=(), env=None):
    options = ("--configuration", configuration, *extra)
    return (
        command("swift", "test", "list", *options, kind="discovery", pattern=pattern, timeout=1800),
        command("swift", "test", *options, "--skip-build", "--filter", pattern,
                kind="xctest", modules=modules, timeout=1800, env=env or {}),
    )


def registry():
    """The sole command definitions used by local runs and the native SDK CI."""
    typography_images = tuple(("{visual}/semantic-typography/table-font-" + slot + "-*.png", "file")
                              for slot in ("header", "body"))
    checks = [
        Check("module-graph", "portable", (
            command("python3", "Tools/check_module_boundaries.py"),
            command("python3", "-c", OBSOLETE_IMPORT_CHECK),
        )),
        Check("source-resources", "portable", (
            command("python3", "-m", "unittest", "discover", "-s", "Tests/ValidationTools", "-p", "test_*.py", kind="unittest"),
            *(command("python3", "Tools/" + name) for name in
              ("check_openui_integration.py", "check_gallery_catalog.py", "check_localization.py")),
        )),
        Check("language-core", "portable", (
            command("npm", "ci", "--prefix", "Tools/Core", "--ignore-scripts"),
            command("node", "Tools/Core/build.mjs"),
            command("git", "diff", "--exit-code", "--", "Sources/SwiftLang/Resources"),
            command("node", "Tools/Core/verify-compatibility.mjs"),
            command("node", "--test", "--test-reporter=tap", "glob:Tools/Core/native-*.test.mjs", kind="node-test"),
            command("node", "--test", "--test-reporter=tap", "Validation/validation.test.mjs", kind="node-test"),
            command("node", "--test", "--test-reporter=tap", "Tools/Presentation/catalog-compatibility.test.mjs", kind="node-test"),
        )),
        Check("presentation-resources", "portable", (
            *(command("npm", "ci", "--prefix", "Tools/Presentation/" + name, "--ignore-scripts")
              for name in ("rich-text", "code-highlighting", "icons")),
            command("node", "Tools/Presentation/rich-text/build.mjs"),
            command("node", "Tools/Presentation/code-highlighting/build.mjs"),
            command("node", "Tools/Presentation/icons/generate.mjs", "--check"),
            command("node", "Tools/Presentation/catalog.mjs", "--check"),
            command("git", "diff", "--exit-code", "--", "Sources/SwiftOpenUI/Resources"),
        )),
        Check("intelligent-ui-math", "portable", (
            command("npm", "ci", "--prefix", "Tools/Functions", "--ignore-scripts"),
            command("node", "Tools/Functions/build-math.cjs"),
            command("node", "--test", "--test-reporter=tap", "Tools/Functions/math-resources.test.cjs", kind="node-test"),
            command("git", "diff", "--exit-code", "--", "Sources/SwiftIntelligentUI/Resources"),
        )),
    ]
    for name, directory in (("core", "Tools/Core"), ("rich-text", "Tools/Presentation/rich-text"),
                            ("code-highlighting", "Tools/Presentation/code-highlighting"),
                            ("icons", "Tools/Presentation/icons"), ("functions", "Tools/Functions")):
        checks.append(Check("dependency-" + name, "security", (
            command("npm", "ci", "--prefix", directory, "--ignore-scripts"),
            command("npm", "audit", "--prefix", directory, "--audit-level=high", "--json"),
        )))
    mac = [
        Check("native-debug-preflight", "macos", filtered_tests(DEBUG_FILTER)),
        Check("intelligent-ui-root-layout", "macos", filtered_tests(
            "OfficialContractParityTests/testRootPercentageHeightUsesTheActualFiniteHostProposal",
            modules=("SwiftIntelligentUITests",), env={"SWIFT_INTELLIGENT_UI_LAYOUT_TRACE": "1"})),
        Check("intelligent-ui-composition", "macos", filtered_tests(COMPOSITION_FILTER, modules=("SwiftIntelligentUITests",))),
        Check("gallery-tests", "macos", (
            command("swift", "test", "--package-path", "Examples/Gallery", "--scratch-path", "{scratch}/gallery-swiftpm",
                    kind="xctest", modules=("OpenUIGalleryTests",), timeout=1800),
        ), tuple(("{visual}/gallery-editorial/" + library + "-*" + suffix, "json" if suffix == ".json" else "file")
                 for library in ("openui", "openintelligentui") for suffix in (".png", ".json"))),
        Check("native-release", "macos", filtered_tests(RELEASE_FILTER, configuration="release", modules=MODULES)),
        Check("native-fitting", "macos", filtered_tests(
            "HostSizingIsolationTests|RuntimeHostIsolationTests", configuration="release",
            modules=("SwiftLangTests", "SwiftOpenUITests"))),
        Check("native-all", "macos", (
            command("swift", "test", "--configuration", "debug", "--scratch-path", "{scratch}/native-coverage",
                    "--enable-code-coverage", kind="xctest", modules=MODULES, timeout=1800),
            command("swift", "test", "--configuration", "debug", "--scratch-path", "{scratch}/native-coverage",
                    "--show-codecov-path", kind="coverage", timeout=120),
        ), (("coverage/coverage.json", "coverage"),) + typography_images),
        Check("consumers", "macos", (
            command("python3", "Tools/check_product_consumers.py", "--scratch-root", "{scratch}/native-consumers", timeout=1800),
        )),
        Check("gallery-programs", "macos", (
            command("swift", "run", "--package-path", "Examples/Gallery", "--scratch-path", "{scratch}/gallery-swiftpm",
                    "OpenUIGallery", "--validate-fixtures", kind="gallery", timeout=1800),
        )),
        Check("gallery-reader-contracts", "macos", (
            command("swift", "run", "--package-path", "Examples/Gallery", "--scratch-path", "{scratch}/gallery-swiftpm",
                    "OpenUIGallery", "--export-contracts", "{output}/contracts", timeout=1800),
        ), (("contracts/openui.json", "json"), ("contracts/openintelligentui.json", "json"))),
        Check("intelligent-ui-contracts", "macos", filtered_tests(
            "OfficialContractParityTests", configuration="release", modules=("SwiftIntelligentUITests",))),
        Check("language-asan", "macos", filtered_tests("SwiftLangTests", extra=(
            "--scratch-path", "{scratch}/openui-asan", "--sanitize=address"), modules=("SwiftLangTests",))),
        Check("contract-tool-build", "macos", (command("swift", "build", "--package-path", "Tools/ContractExport", timeout=1800),)),
        Check("performance-tool-build", "macos", (
            command("swift", "build", "--configuration", "release", "--package-path", "Validation/Performance", timeout=1800),
        )),
    ]
    for units in (24, 128):
        mac.append(Check("performance-" + str(units), "macos", (
            command("swift", "run", "--configuration", "release", "--package-path", "Validation/Performance",
                    "LanguagePerformanceValidation", "--iterations", "100", "--warmup", "5", "--rows", "200",
                    "--stream-iterations", "5", "--chunk-units", str(units),
                    "--output", "{output}/performance/language-stream-" + str(units) + ".json", timeout=1800),
        ), (("performance/language-stream-" + str(units) + ".json", "performance"),)))
    checks += [Check(c.id, c.profile, c.commands, c.required, "Darwin") for c in mac]
    checks.append(Check("ios-native", "ios", (
        command("python3", "Validation/SDK/ios.py", "--output", "{output}/ios", timeout=3600),
    ), (("ios/summary.json", "ios"),) + typography_images, "Darwin"))
    return checks


def utc():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def git(root, *args):
    return subprocess.check_output(["git", *args], cwd=root, stderr=subprocess.PIPE, timeout=30)


def provenance(root):
    status = git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all")
    changes = hashlib.sha256(git(root, "diff", "--binary", "HEAD", "--"))
    for name in sorted(git(root, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0")):
        if not name:
            continue
        path = root / os.fsdecode(name)
        changes.update(name)
        changes.update(os.fsencode(os.readlink(path)) if path.is_symlink() else digest(path).encode())
    commit = git(root, "rev-parse", "HEAD").decode().strip()
    return {"commit": commit, "dirty": bool(status), "statusPorcelain": status.decode(errors="replace"),
            "fingerprint": hashlib.sha256(commit.encode() + status + changes.digest()).hexdigest(),
            "runnerSHA256": digest(__file__)}


def environment():
    tools = {}
    for name, arguments in (("git", ["--version"]), ("node", ["--version"]), ("npm", ["--version"]),
                            ("swift", ["--version"]), ("xcodebuild", ["-version"]), ("sw_vers", [])):
        executable = shutil.which(name)
        value = {"path": executable}
        if executable:
            try:
                result = subprocess.run([executable, *arguments], capture_output=True, text=True, timeout=15)
                value.update(exitCode=result.returncode, version=(result.stdout + result.stderr).strip())
            except (OSError, subprocess.TimeoutExpired) as error:
                value["error"] = str(error)
        tools[name] = value
    return {"system": platform.system(), "platform": platform.platform(), "architecture": platform.machine(),
            "processorCount": os.cpu_count(), "python": sys.version, "tools": tools,
            "ci": {name: os.environ[name] for name in ("CI", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_JOB") if name in os.environ},
            "developerDirectory": os.environ.get("DEVELOPER_DIR")}


def prepare_output(path):
    path = Path(path)
    if path.is_symlink() or (path.exists() and (not path.is_dir() or any(path.iterdir()))):
        raise ValueError("Output must be a new or empty directory: " + str(path))
    path.mkdir(parents=True, exist_ok=True)
    return path.resolve()


def atomic_write(path, data):
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def inventory(checks):
    return [{"id": check.id, "profile": check.profile} for check in checks]


def save_report(output, report):
    states = {check["id"]: check["status"] for check in report.get("checks", [])}
    report["unselectedChecks"] = [check["id"] for check in report["registeredChecks"] if check["id"] not in states]
    report["profiles"] = []
    for profile in PROFILES:
        required = [check["id"] for check in report["registeredChecks"] if check["profile"] == profile]
        selected = [identifier for identifier in required if identifier in states]
        passed = [identifier for identifier in required if states.get(identifier) == "passed"]
        status = ("not-selected" if not selected else "passed" if len(passed) == len(required)
                  else "failed" if any(states[identifier] in ("failed", "unavailable", "timed-out", "cancelled")
                                       for identifier in selected) else "incomplete")
        report["profiles"].append({"id": profile, "status": status, "requiredChecks": required,
                                   "selectedChecks": selected, "passedChecks": passed})
    report["coverageReference"] = "Validation/SDK/README.md"
    commit = report.get("provenance", {}).get("commit", report.get("expectedSHA", "unavailable"))
    repository = os.environ.get("GITHUB_REPOSITORY", "zyfn/open-intelligent-ui-swift")
    reference = (f"https://github.com/{repository}/blob/{commit}/{report['coverageReference']}"
                 if re.fullmatch(r"[0-9a-f]{40}", commit) else report["coverageReference"])
    lines = ["# SDK validation execution", "", f"Status: **{report['status']}**", "",
             "This result describes the selected checks; unselected checks are not implied to have passed.", "",
             f"Commit: `{report.get('provenance', {}).get('commit', report.get('expectedSHA', 'unavailable'))}`", "",
             f"[Coverage, manual review and physical-device requirements]({reference})", "",
             "| Profile | Execution | Passed / required checks |", "| --- | --- | --- |"]
    lines += [f"| {p['id']} | {p['status']} | {len(p['passedChecks'])} / {len(p['requiredChecks'])} |" for p in report["profiles"]]
    lines += ["", "| Check | Profile | Execution |", "| --- | --- | --- |"]
    lines += [f"| {c['id']} | {c['profile']} | {c['status']} |" for c in report.get("checks", [])]
    lines += ["", "Unselected checks: " + (", ".join(report["unselectedChecks"]) or "None."), ""]
    if report.get("errors"):
        lines += ["## Execution/report errors", "", *["- " + str(error) for error in report["errors"]], ""]
    atomic_write(output / "summary.md", "\n".join(lines) + "\n")
    report["summary"] = {"path": "summary.md", "sha256": digest(output / "summary.md"), "size": (output / "summary.md").stat().st_size}
    atomic_write(output / "report.json", json.dumps(report, ensure_ascii=False, indent=2) + "\n")


def stop_process(process):
    # A compiler/test can spawn children. Terminating only its immediate parent
    # leaves work running after a timeout or cancellation.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        # The iOS helper owns a separate xcodebuild process group and needs up
        # to ten seconds to terminate it before escalating to SIGKILL.
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


class Interrupted(Exception):
    def __init__(self, signum):
        self.signum = signum


def expand(text, values):
    for key, value in values.items():
        text = text.replace("{" + key + "}", str(value))
    return text


def inspect_log(spec, log, result, values, started_ns):
    text = log.read_text(errors="replace")
    if spec.kind == "discovery":
        tests = re.findall(r"^([A-Za-z_][\w]*\.[\w]+/[\w]+)\s*$", text, re.M)
        selected = [name for name in tests if re.search(spec.pattern or ".", name)]
        result["observed"] = {"discoveredTests": len(tests), "selectedTests": len(selected), "filter": spec.pattern}
        if not selected:
            raise ValueError("Test discovery matched zero tests")
    elif spec.kind == "xctest":
        events = re.findall(r"Test Case ['\"]-?\[?([\w]+)\.[^\n]+?['\"] (passed|failed|skipped)\b", text)
        executed = [module for module, status in events if status in ("passed", "failed")]
        result["observed"] = {"executedTests": len(executed), "skippedTests": sum(status == "skipped" for _, status in events),
                              "byModule": {module: executed.count(module) for module in sorted(set(executed))}}
        if not executed or any(module not in executed for module in spec.modules):
            raise ValueError("No executed XCTest cases for all required modules: " + ", ".join(spec.modules))
        if any(status == "failed" for _, status in events):
            raise ValueError("XCTest failure reported despite a successful process exit")
    elif spec.kind in ("node-test", "unittest"):
        pattern = r"^# tests (\d+)\s*$" if spec.kind == "node-test" else r"Ran (\d+) tests? in "
        counts = [int(count) for count in re.findall(pattern, text, re.M)]
        if not counts or max(counts) == 0:
            raise ValueError("Test command did not report executed tests")
        if spec.kind == "node-test":
            totals = {key: int(value) for key, value in re.findall(r"^# (pass|fail|cancelled|skipped) (\d+)\s*$", text, re.M)}
            if totals.get("pass", 0) == 0 or totals.get("fail") != 0 or totals.get("cancelled") != 0:
                raise ValueError("Node tests had no passes or reported failures/cancellation")
            result["observed"] = {"reportedTests": max(counts), **totals, "executedTests": totals["pass"]}
        else:
            skipped = sum(int(value) for value in re.findall(r"skipped=(\d+)", text))
            if max(counts) <= skipped or not re.search(r"^OK(?: \([^\n]*\))?\s*$", text, re.M):
                raise ValueError("unittest had no executed tests or did not report success")
            result["observed"] = {"reportedTests": max(counts), "skippedTests": skipped, "executedTests": max(counts) - skipped}
    elif spec.kind == "gallery":
        matches = re.findall(r"Validated (\d+) Gallery variants; batch=(\d+), streamed=(\d+), failures=(\d+)", text)
        if len(matches) != 1:
            raise ValueError("Missing or ambiguous Gallery validation summary")
        variants, batch, streamed, failures = map(int, matches[0])
        if variants == 0 or variants != batch or streamed != variants * 3 or failures:
            raise ValueError("Gallery did not validate every variant in batch and all three streaming partitions")
        result["observed"] = dict(variants=variants, batch=batch, streamed=streamed, partitionsPerVariant=3, failures=failures)
    elif spec.kind == "coverage":
        paths = [Path(line.strip()) for line in text.splitlines() if line.strip().startswith("/") and line.strip().endswith(".json")]
        if len(paths) != 1 or not paths[0].is_file() or paths[0].stat().st_mtime_ns < started_ns:
            raise ValueError("Coverage export is missing, ambiguous, or older than this check")
        target = Path(values["output"]) / "coverage/coverage.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(paths[0], target)
        result["observed"] = {"coverageSource": str(paths[0]), "coveragePercentThreshold": None}


def run_command(spec, result, root, values, log, started_ns):
    arguments = []
    for argument in spec.argv:
        argument = expand(argument, values)
        if argument.startswith("glob:"):
            matches = [str(Path(path).relative_to(root)) for path in sorted(glob.glob(str(root / argument[5:])))]
            if not matches:
                raise ValueError("Command input glob matched no files: " + argument[5:])
            arguments.extend(matches)
        else:
            arguments.append(argument)
    overrides = {"OPENUI_RUNTIME_TELEMETRY_ENABLED": "0", "OPENUI_SNAPSHOT_DIR": str(values["visual"]), **spec.env}
    result.update(argv=arguments, cwd=str(root), environment=overrides, timeoutSeconds=spec.timeout, startedAt=utc(), status="running")
    started = time.monotonic()
    process = None
    try:
        with log.open("wb") as stream:
            process = subprocess.Popen(arguments, cwd=root, env={**os.environ, **overrides}, stdout=stream,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                result["exitCode"] = process.wait(timeout=spec.timeout)
            except subprocess.TimeoutExpired:
                stop_process(process)
                result.update(status="timed-out", exitCode=process.returncode, reason="Command timeout expired")
                return
        if result["exitCode"] != 0:
            result.update(status="failed", reason="Command exited unsuccessfully")
            return
        inspect_log(spec, log, result, values, started_ns)
        result["status"] = "passed"
    except FileNotFoundError as error:
        result.update(status="unavailable", reason=str(error), exitCode=None)
    except Interrupted:
        if process is not None:
            stop_process(process)
        result.update(status="cancelled", exitCode=process.returncode if process else None, reason="Run interrupted")
        raise
    finally:
        result.update(finishedAt=utc(), durationSeconds=round(time.monotonic() - started, 6))


def artifact(path, output):
    if path.is_symlink() or not path.resolve().is_relative_to(output.resolve()):
        raise ValueError("Artifact must be a regular file inside this run: " + str(path))
    return {"path": path.relative_to(output).as_posix(), "size": path.stat().st_size, "sha256": digest(path)}


def verify_required(check, values):
    verified = []
    for pattern, kind in check.required:
        expression = expand(pattern, values)
        path = Path(expression)
        if not path.is_absolute():
            expression = str(Path(values["output"]) / expression)
        matches = [Path(name) for name in glob.glob(expression, recursive=True) if Path(name).is_file()]
        if not matches:
            raise ValueError("Required artifact missing: " + pattern)
        for candidate in matches:
            verified.append(candidate)
            if candidate.stat().st_size == 0:
                raise ValueError("Required artifact is empty: " + str(candidate))
            if kind in ("json", "performance", "coverage", "ios"):
                data = json.loads(candidate.read_text())
                if not isinstance(data, dict):
                    raise ValueError("Required artifact must contain a JSON object: " + str(candidate))
                if kind == "performance":
                    if data.get("workload") != "language-runtime" or data.get("configuration") != "release":
                        raise ValueError("Unexpected performance report identity/configuration")
                    streaming = data.get("streaming", {})
                    if not isinstance(streaming, dict):
                        raise ValueError("Missing streaming performance measurements")
                    for section, keys in ((data, ("iterations", "programBytes", "components")),
                                          (streaming, ("iterations", "chunksPerIteration", "chunkUTF16Units", "sourceUTF16Units"))):
                        if any(type(section.get(key)) is not int or section[key] <= 0 for key in keys):
                            raise ValueError("Performance report has no measured workload samples")
                    for section in (data, *(streaming.get(key, {}) for key in ("push", "complete", "wholeStream"))):
                        if not isinstance(section, dict) or any(type(section.get(key)) not in (int, float)
                                or not math.isfinite(section[key]) or section[key] < 0
                                for key in ("p50Milliseconds", "p95Milliseconds", "maxMilliseconds")):
                            raise ValueError("Missing or invalid performance measurements")
                    for spec in check.commands:
                        for flag, actual in (("--iterations", data["iterations"]),
                                             ("--stream-iterations", streaming["iterations"]),
                                             ("--chunk-units", streaming["chunkUTF16Units"])):
                            if flag in spec.argv and int(spec.argv[spec.argv.index(flag) + 1]) != actual:
                                raise ValueError("Performance report does not match " + flag)
                if kind == "coverage":
                    exports = data.get("data")
                    if data.get("type") != "llvm.coverage.json.export" or not isinstance(exports, list) or not exports \
                            or not any(isinstance(item, dict) and isinstance(item.get("files"), list)
                                       and item["files"] and isinstance(item.get("totals"), dict) for item in exports):
                        raise ValueError("Missing file-level LLVM coverage measurements")
                if kind == "ios":
                    results = data.get("testResults", {})
                    if data.get("status") != "passed" or not isinstance(results, dict):
                        raise ValueError("iOS summary does not report successful native tests")
                    targets = results.get("targets", {})
                    if not isinstance(targets, dict):
                        raise ValueError("iOS summary has invalid target results")
                    for key in ("totalTestCount", "passedTests", "failedTests", "skippedTests"):
                        if type(results.get(key)) is not int or results[key] < 0:
                            raise ValueError("Invalid iOS test count: " + key)
                    if results["failedTests"] or results["passedTests"] == 0 or results["totalTestCount"] < results["passedTests"]:
                        raise ValueError("No successful iOS test executions")
                    for module in MODULES:
                        target = targets.get(module, {})
                        if not isinstance(target, dict) or type(target.get("passed")) is not int \
                                or target["passed"] <= 0 or target.get("failed") != 0:
                            raise ValueError("Missing successful iOS target: " + module)
    return verified


def collect_crashes(output, started_ns):
    if platform.system() != "Darwin":
        return []
    source = Path.home() / "Library/Logs/DiagnosticReports"
    destination = output / "crash-reports"
    paths = []
    if source.is_dir():
        for path in source.iterdir():
            if path.is_file() and ("PackageTests" in path.name or path.name.startswith("xctest")) \
                    and path.suffix in (".ips", ".crash") and path.stat().st_mtime_ns >= started_ns:
                destination.mkdir(exist_ok=True)
                target = destination / path.name
                shutil.copyfile(path, target)
                paths.append(artifact(target, output))
    return paths


def execute(checks, output, root=ROOT, selection=None, registered=None):
    if not checks or any(not check.commands for check in checks) or len({check.id for check in checks}) != len(checks):
        raise ValueError("Execution requires a nonempty, unique check selection")
    output = prepare_output(output)
    registered = registry() if registered is None else registered
    report = {"schemaVersion": 1, "kind": "sdk-validation-run", "status": "running", "startedAt": utc(),
              "selection": selection or {"checkIds": [c.id for c in checks]}, "registeredChecks": inventory(registered),
              "checks": [{"id": c.id, "profile": c.profile, "status": "not-run", "commands": [], "artifacts": []} for c in checks],
              "errors": [], "artifacts": []}
    started_ns = time.time_ns()
    previous_handlers, interrupted = {}, None
    def handler(signum, _frame):
        raise Interrupted(signum)
    try:
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[signum] = signal.signal(signum, handler)
        save_report(output, report)
        report["provenance"] = provenance(root)
        report["environment"] = environment()
        save_report(output, report)
        with tempfile.TemporaryDirectory(prefix="sdk-validation-") as scratch:
            for check, result in zip(checks, report["checks"]):
                check_dir = output / "checks" / check.id
                check_dir.mkdir(parents=True)
                visual = output / "visual" / check.id
                values = {"repo": root, "output": check_dir, "scratch": scratch, "visual": visual}
                result.update(status="running", startedAt=utc())
                check_started_ns = time.time_ns()
                print(f"[{check.profile}] {check.id}", flush=True)
                save_report(output, report)
                try:
                    if check.system and platform.system() != check.system:
                        result.update(status="unavailable", reason="Requires " + check.system)
                    else:
                        for index, spec in enumerate(check.commands, 1):
                            log = check_dir / f"command-{index:02d}.log"
                            outcome = {"status": "running", "argv": list(spec.argv), "kind": spec.kind,
                                       "exitCode": None, "log": log.relative_to(output).as_posix()}
                            result["commands"].append(outcome)
                            save_report(output, report)
                            try:
                                run_command(spec, outcome, root, values, log, check_started_ns)
                            except (OSError, ValueError) as error:
                                outcome.update(status="failed", reason=str(error))
                            if outcome["status"] != "passed":
                                result.update(status=outcome["status"], reason=outcome.get("reason", "Command failed"))
                                break
                        else:
                            verify_required(check, values)
                            result["status"] = "passed"
                except Interrupted:
                    result.update(status="cancelled", reason="Run interrupted")
                    raise
                except (OSError, ValueError) as error:
                    result.update(status="failed", reason=str(error))
                finally:
                    result["finishedAt"] = utc()
                    result["artifacts"] = [artifact(p, output) for directory in (check_dir, visual)
                                           if directory.exists() for p in sorted(directory.rglob("*")) if p.is_file()]
                    save_report(output, report)
    except Interrupted as error:
        interrupted = error.signum
        report["errors"].append("Cancelled by signal " + str(error.signum))
    except Exception as error:
        report["errors"].append(type(error).__name__ + ": " + str(error))
    finally:
        for signum, previous in previous_handlers.items():
            signal.signal(signum, previous)
        try:
            report["provenanceEnd"] = provenance(root)
            if report.get("provenance", {}).get("fingerprint") != report["provenanceEnd"]["fingerprint"]:
                report["errors"].append("Source checkout changed during validation")
            report["artifacts"] = collect_crashes(output, started_ns)
        except Exception as error:
            report["errors"].append("Final evidence collection: " + str(error))
        report["status"] = "cancelled" if interrupted else (
            "passed" if not report["errors"] and all(c["status"] == "passed" for c in report["checks"]) else "failed")
        report["finishedAt"] = utc()
        save_report(output, report)
    return (128 + interrupted) if interrupted else (0 if report["status"] == "passed" else 1)


def verify_artifact(item, output):
    path = Path(item["path"])
    if path.is_absolute() or ".." in path.parts:
        raise ValueError("Unsafe artifact path: " + str(path))
    actual = artifact(output / path, output)
    if actual != item:
        raise ValueError("Artifact size/hash mismatch: " + str(path))


def collect(inputs, output, expected_sha, checks=None):
    checks = registry() if checks is None else checks
    output = prepare_output(output)
    report = {"schemaVersion": 1, "kind": "sdk-validation-collection", "status": "failed", "expectedSHA": expected_sha,
              "startedAt": utc(), "requiredProfiles": list(PROFILES), "registeredChecks": inventory(checks),
              "checks": [], "errors": [], "reports": []}
    known, seen = {c.id: c for c in checks}, set()
    paths = []
    for source in inputs:
        # An expanded {visual} path must not be mistaken for a path relative
        # to the check directory when the caller supplies a relative input.
        source = Path(source).resolve()
        paths += [source] if source.is_file() else sorted(source.rglob("report.json"))
    if not paths:
        report["errors"].append("No execution reports found")
    for path in paths:
        try:
            data = json.loads(path.read_text())
            if data.get("schemaVersion") != 1 or data.get("kind") != "sdk-validation-run":
                raise ValueError("Not a supported execution report")
            before, after = data.get("provenance", {}), data.get("provenanceEnd", {})
            if before.get("commit") != expected_sha or after.get("commit") != expected_sha:
                raise ValueError("Report commit does not match expected SHA")
            if before.get("dirty") is not False or after.get("dirty") is not False:
                raise ValueError("CI acceptance requires a clean checkout")
            if not before.get("fingerprint") or before.get("fingerprint") != after.get("fingerprint"):
                raise ValueError("Source fingerprint changed or is missing")
            if before.get("runnerSHA256") != digest(__file__) or data.get("registeredChecks") != inventory(checks):
                raise ValueError("Runner or registered checks differ from the collector")
            if data.get("status") != "passed" or not data.get("finishedAt") or data.get("errors"):
                raise ValueError("Execution was failed, cancelled, incomplete, or not finalized")
            entries = data.get("checks", [])
            if not entries or data.get("selection", {}).get("checkIds") != [c["id"] for c in entries]:
                raise ValueError("Check selection is empty or differs from results")
            for entry in entries:
                identifier = entry["id"]
                if identifier not in known or identifier in seen:
                    raise ValueError("Unknown or duplicate check: " + identifier)
                seen.add(identifier)
                if entry.get("profile") != known[identifier].profile or entry.get("status") != "passed":
                    raise ValueError("Check profile/status mismatch: " + identifier)
                if len(entry.get("commands", [])) != len(known[identifier].commands) or any(
                        c.get("status") != "passed" or c.get("exitCode") != 0 for c in entry.get("commands", [])):
                    raise ValueError("Check commands did not all execute successfully: " + identifier)
                if not entry.get("artifacts"):
                    raise ValueError("Missing saved command evidence: " + identifier)
                recorded_paths = {item["path"] for item in entry["artifacts"]}
                if any(c.get("log") not in recorded_paths for c in entry["commands"]):
                    raise ValueError("Command log was not retained and hashed: " + identifier)
                for item in entry["artifacts"]:
                    verify_artifact(item, path.parent)
                values = {"output": path.parent / "checks" / identifier, "visual": path.parent / "visual" / identifier}
                required = verify_required(known[identifier], values)
                if any(p.relative_to(path.parent).as_posix() not in recorded_paths for p in required):
                    raise ValueError("Required artifact was not retained and hashed: " + identifier)
                report["checks"].append({**entry, "sourceReport": str(path)})
            for item in [*data.get("artifacts", []), data["summary"]]:
                verify_artifact(item, path.parent)
            report["reports"].append({"path": str(path), "sha256": digest(path)})
        except (OSError, ValueError, KeyError, TypeError) as error:
            report["errors"].append(str(path) + ": " + str(error))
    missing = sorted(set(known) - seen)
    if missing:
        report["errors"].append("Missing required checks: " + ", ".join(missing))
    if {entry["profile"] for entry in report["checks"]} != set(PROFILES):
        report["errors"].append("All four required profiles must have complete execution evidence")
    report["status"] = "passed" if not report["errors"] else "failed"
    report["finishedAt"] = utc()
    save_report(output, report)
    return 0 if report["status"] == "passed" else 1


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    if arguments and arguments[0] == "collect":
        parser = argparse.ArgumentParser(description="Verify all four profiles and their saved evidence")
        parser.add_argument("--input", action="append", required=True, type=Path)
        parser.add_argument("--output", required=True, type=Path)
        parser.add_argument("--expected-sha", required=True)
        args = parser.parse_args(arguments[1:])
        if not re.fullmatch(r"[0-9a-f]{40}", args.expected_sha):
            parser.error("--expected-sha must be the full commit SHA")
        return collect(args.input, args.output, args.expected_sha)
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--profile", choices=(*PROFILES, "all"))
    selection.add_argument("--check", action="append")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args(arguments)
    checks = registry()
    if args.list:
        print(json.dumps({"profiles": {p: [c.id for c in checks if c.profile == p] for p in PROFILES},
                          "checks": [{"id": c.id, "profile": c.profile, "system": c.system,
                                      "commands": [list(command.argv) for command in c.commands]} for c in checks]}, indent=2))
        return 0
    if not args.output:
        parser.error("--output is required for execution")
    if args.check:
        known = {c.id for c in checks}
        if len(set(args.check)) != len(args.check) or any(c not in known for c in args.check):
            parser.error("--check values must be known, unique IDs")
        selected = [c for c in checks if c.id in args.check]
    else:
        selected = [c for c in checks if args.profile in (None, "all", c.profile)]
    return execute(selected, args.output,
                   selection={"profile": args.profile or (None if args.check else "all"), "checkIds": [c.id for c in selected]})


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("SDK validation: " + str(error), file=sys.stderr)
        raise SystemExit(2)
