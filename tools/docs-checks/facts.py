#!/usr/bin/env python3
"""Check that the docs state what the workflows and dependabot.yml say.

Needs PyYAML (requirements.txt); run from anywhere: python3 tools/docs-checks/facts.py

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

import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
RULESETS = ROOT / "docs/markDown/engineering/ci-cd/rulesets.md"
DEPENDABOT_DOC = ROOT / "docs/markDown/engineering/ci-cd/dependabot.md"
DEPENDABOT_YML = ROOT / ".github/dependabot.yml"
ITEM = re.compile(r"^\d+\. `([^`]+)`: (?:.*?`([\w.-]+\.yaml)`.*?, )?job `([\w-]+)`")
FILE_LINK = re.compile(r"\[`([\w.-]+\.yaml)`\]")
errors = []


def jobs(workflow):
    """{job id: job name} of a workflow file."""
    data = yaml.safe_load((WORKFLOWS / workflow).read_text())
    return {job: (body or {}).get("name", job) for job, body in data["jobs"].items()}


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


def dependabot_entries(text):
    """[(kind, value)] for every ecosystem and directory in dependabot.yml."""
    found = []
    for update in yaml.safe_load(text)["updates"]:
        found.append(("package-ecosystem", update["package-ecosystem"]))
        for directory in [update.get("directory"), *update.get("directories", [])]:
            if directory is not None:
                found.append(("directory", directory))
    return found


def check_dependabot():
    doc = DEPENDABOT_DOC.read_text()
    for key, value in dependabot_entries(DEPENDABOT_YML.read_text()):
        needle = value.strip("/") or None
        if key == "package-ecosystem":
            needle = {"github-actions": "GitHub Actions", "pip": "Python", "npm": "npm", "docker": "docker"}.get(value)
            if needle is None:
                errors.append(f"dependabot.md: no docs name known for ecosystem {value}")
                continue
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
