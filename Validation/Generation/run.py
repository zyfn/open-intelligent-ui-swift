#!/usr/bin/env python3
"""Optional model generation evaluation through the existing Codex login. No key storage."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import re
import os

def sanitized(text):
    text = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+", r"\1[REDACTED]", text)
    return re.sub(r"(?i)([?&](?:access_token|refresh_token|token|code)=)[^&\s\"<>]+", r"\1[REDACTED]", text)

parser = argparse.ArgumentParser()
parser.add_argument("--timeout", type=int, default=120)
parser.add_argument("--model", choices=["gpt-6-terra", "gpt-6.1-terra"], default="gpt-6.1-terra")
parser.add_argument("--client", default=os.environ.get("CODEX_APP_RUNTIME_CLI_PATH", "codex"))
parser.add_argument("--suite", choices=["all", "guided", "free"], default="all")
parser.add_argument("--case", action="append", dest="case_ids", help="Run only these case ids; repeat for several cases")
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
suite = Path(__file__).resolve().parent
model_output = root / "outputs" / "generation" / args.model
output = model_output / time.strftime("%Y%m%d-%H%M%S")
output.mkdir(parents=True, exist_ok=True)
prompt = (root / "outputs/contracts/prompt.txt").read_text()
cases = json.loads((suite / "cases.json").read_text())
if args.suite != "all":
    cases = [case for case in cases if case.get("mode", "guided") == args.suite]
if args.case_ids:
    unknown = set(args.case_ids) - {case["id"] for case in cases}
    if unknown: parser.error("Unknown case id(s): " + ", ".join(sorted(unknown)))
    cases = [case for case in cases if case["id"] in args.case_ids]
expanded = []
for case in cases:
    expanded.append(case)
    previous = case["id"]
    for index, task in enumerate(case.get("followups", []), 1):
        identifier = case["id"] + "-followup-" + str(index)
        expanded.append({"id": identifier, "task": task, "sourceTask": case["task"],
                         "previousCase": previous, "mode": case.get("mode", "guided"),
                         "review": case.get("review", [])})
        previous = identifier
cases = expanded
previous_programs = {}
client = args.client
client_version = subprocess.run([client, "--version"], text=True, capture_output=True).stdout.strip()
report = {"requestedModel": args.model, "actualModel": None, "clientVersion": client_version, "runDirectory": str(output),
          "promptSHA256": hashlib.sha256(prompt.encode()).hexdigest(), "requestedCases": [case["id"] for case in cases], "cases": [], "status": "running"}
for case in cases:
    answer = output / (case["id"] + ".json")
    request = "You are being evaluated only as a UI generator. Do not use tools or access files. Return only the requested JSON containing a program.\n\n" + prompt + "\n\nTask:\n" + case["task"]
    if case.get("previousCase"):
        previous = previous_programs.get(case["previousCase"])
        if previous is None:
            report["cases"].append({"id": case["id"], "status": "blocked", "reason": "previous turn produced no program"})
            report["status"] = "blocked"
            break
        request += "\n\nPrevious task facts:\n" + case["sourceTask"]
        request += "\n\nPrevious generated program (context, not new source facts):\n" + previous
        request += "\n\nCurrent follow-up request:\n" + case["task"]
    (output / (case["id"] + ".prompt.txt")).write_text(request)
    command = [client, "exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
               "--model", args.model, "--json", "--output-schema", str(suite / "response-schema.json"),
               "--output-last-message", str(answer), "-"]
    start = time.monotonic()
    try:
        result = subprocess.run(command, input=request, text=True, capture_output=True, cwd=output, timeout=args.timeout)
        (output / (case["id"] + ".events.jsonl")).write_text(sanitized(result.stdout))
        (output / (case["id"] + ".stderr.log")).write_text(sanitized(result.stderr))
        entry = {"id": case["id"], "seconds": round(time.monotonic() - start, 2), "exitCode": result.returncode}
        if result.returncode != 0 or not answer.exists():
            entry["status"] = "blocked"
            for line in result.stdout.splitlines():
                try:
                    event = json.loads(line)
                    if event.get("type") == "error": report["reason"] = sanitized(event.get("message", ""))
                except ValueError:
                    pass
            report["cases"].append(entry); report["status"] = "blocked"; break
        validation = subprocess.run(["swift", "run", "--package-path", str(root / "Tools/ContractExport"),
                                     "--skip-build", "ContractExport", "--validate", str(answer), "--case", case["id"]],
                                    cwd=root, text=True, capture_output=True)
        entry["status"] = "runtime-passed" if validation.returncode == 0 else "runtime-failed"
        entry["validation"] = validation.stdout
        entry["validationDiagnostics"] = sanitized(validation.stderr)
        entry["mode"] = case.get("mode", "guided")
        entry["reviewCriteria"] = case.get("review", [])
        entry["presentationReview"] = "pending"
        entry["sourceFidelityReview"] = "pending"
        entry["interactionReview"] = "pending"
        try:
            previous_programs[case["id"]] = json.loads(answer.read_text())["program"]
        except (ValueError, KeyError):
            entry["status"] = "runtime-failed"
        report["cases"].append(entry)
    except subprocess.TimeoutExpired:
        report["cases"].append({"id": case["id"], "status": "timeout"})
        report["status"] = "blocked"; break
if report["status"] == "running":
    report["status"] = "runtime-passed-ui-review-pending" if all(case["status"] == "runtime-passed" for case in report["cases"]) else "runtime-failed"
report["modelIdentityEvidence"] = "Explicit model requested through the recorded Codex client; CLI does not expose the provider response model ID."
(output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
(model_output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps(report, ensure_ascii=False, indent=2))
raise SystemExit(2 if report["status"] == "blocked" else 1 if report["status"] == "runtime-failed" else 0)
