#!/usr/bin/env python3
"""Check that the docs state what the workflows and dependabot.yml say.

Stdlib only; run from anywhere: python3 tools/docs-checks/facts.py

1. rulesets.md lists the required checks as "`<check name>`: `<workflow>`,
   job `<id>`". Each must be a job with that id and name in that workflow
   (a workflow file named once covers the items after it), and every
   "N required checks" in the Markdown must equal the length of that list.
2. Every package ecosystem and directory in dependabot.yml appears in
   dependabot.md.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
RULESETS = ROOT / "docs/markDown/engineering/ci-cd/rulesets.md"
DEPENDABOT_DOC = ROOT / "docs/markDown/engineering/ci-cd/dependabot.md"
DEPENDABOT_YML = ROOT / ".github/dependabot.yml"
ITEM = re.compile(r"^\d+\. `([^`]+)`: (?:.*?`([\w.-]+\.yaml)`.*?, )?job `([\w-]+)`")
FILE_LINK = re.compile(r"\[`([\w.-]+\.yaml)`\]")
# A Dependabot line: `package-ecosystem: x`, `directory: x` or a `- x` list
# item that is a path; x is "double-quoted", 'single-quoted' or bare, and may
# be followed by a comment.
SCALAR = r"""(?:"([^"]*)"|'([^']*)'|([^"'#\s][^#]*?))\s*(?:#.*)?$"""
ENTRY = re.compile(rf"\s*(?:- )?(package-ecosystem|directory):\s*{SCALAR}|\s*- (?:\"(/[^\"]*)\"|'(/[^']*)'|(/[^#\s]*))\s*(?:#.*)?$")
errors = []


def jobs(workflow):
    """{job id: job name} of a workflow file, read line by line."""
    found, current, in_jobs = {}, None, False
    for line in (WORKFLOWS / workflow).read_text().splitlines():
        if line.startswith("jobs:"):
            in_jobs = True
        elif in_jobs and (job := re.match(r"^  ([\w-]+):\s*(?:#.*)?$", line)):
            current = job.group(1)
            found[current] = current
        elif in_jobs and current and (name := re.match(r"^    name:\s*(?:\"([^\"]*)\"|'([^']*)'|([^#\s][^#]*?))\s*(?:#.*)?$", line)):
            found[current] = next(g for g in name.groups() if g is not None)
    return found


def check_required_checks():
    section = RULESETS.read_text().split("## Required status checks", 1)[1]
    workflow, count = None, 0
    for line in section.splitlines():
        if line.startswith("## "):
            break
        item = ITEM.match(line)
        if not item:
            continue
        count += 1
        name, job = item.group(1), item.group(3)
        link = FILE_LINK.search(line)
        workflow = (link and link.group(1)) or item.group(2) or workflow
        if workflow is None or not (WORKFLOWS / workflow).exists():
            errors.append(f"rulesets.md: check {count} ({name}): workflow {workflow} not found")
        elif jobs(workflow).get(job) != name:
            errors.append(f"rulesets.md: check {count}: {workflow} job {job} is named {jobs(workflow).get(job)!r}, not {name!r}")
    if count == 0:
        errors.append("rulesets.md: no required checks found")
    for path in [*ROOT.glob("*.md"), *(ROOT / "docs").rglob("*.md")]:
        for number in re.findall(r"\b(\d+) required checks\b", path.read_text()):
            if int(number) != count:
                errors.append(f"{path.relative_to(ROOT)}: says {number} required checks, rulesets.md lists {count}")
    return count


def read_entry(line):
    """(key, value) of a Dependabot line, None if it is not one, or
    (key, None) if it is one whose value cannot be read in full."""
    match = ENTRY.match(line)
    if match:
        return match.group(1) or "directory", next(g for g in match.groups()[1:] if g is not None)
    key = re.match(r"\s*(?:- )?(package-ecosystem|directory):", line)
    if key:
        return key.group(1), None
    return None


def check_dependabot():
    doc = DEPENDABOT_DOC.read_text()
    for line in DEPENDABOT_YML.read_text().splitlines():
        entry = read_entry(line)
        if entry is None:
            continue
        key, value = entry
        if value is None:
            errors.append(f"dependabot.yml: cannot read the value in {line.strip()!r}")
            continue
        needle = value.strip("/") if value != "/" else None
        if key == "package-ecosystem":
            needle = {"github-actions": "GitHub Actions", "pip": "Python", "npm": "npm", "docker": "docker"}[value]
        if needle and needle not in doc:
            errors.append(f"dependabot.md: does not mention {needle} (dependabot.yml: {value})")


if __name__ == "__main__":
    count = check_required_checks()
    check_dependabot()
    for error in errors:
        print(f"::error::{error}")
    if errors:
        sys.exit(1)
    print(f"Docs match the workflows: {count} required checks, Dependabot ecosystems and folders")
