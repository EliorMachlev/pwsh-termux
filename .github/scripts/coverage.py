#!/usr/bin/env python3
"""Measure how much of scripts/ the tests run, and fail below a floor.

Usage:
  coverage.py run <trace-dir> -- <command...>
      Run the command with every Bash process it starts traced: each one
      sources a small file through BASH_ENV that turns on xtrace, writing
      "<file>|<line>" for every command it runs to its own file in
      <trace-dir>. Exits with the command's status.
  coverage.py report <trace-dir> [--python-json FILE] [--shfmt PATH]
                     [--fail-under-bash N] [--fail-under-python N]
                     [--fail-under-total N]
      Read the traces and print the coverage of each script, and the
      coverage.py JSON report of the Python, with the totals. Exits 1 if a
      total is below its floor (a percentage).

What counts, for Bash: the lines that start a command. shfmt's parser
(shfmt --to-json, so not a guess from the text) gives every simple command
(a command, an assignment, `local`/`export`/`readonly`, `[[ ]]`, `(( ))`)
with its first and last line, including the conditions of `if` and `while`
and the commands inside functions. A line is covered when Bash traced a
command on any line of a command that starts there (Bash reports a command
written over several lines by one of them). Two commands on one line are one
line: this is line coverage, as kcov and bashcov report it. Function
definitions, `then`/`fi`/`done`, comments and blank lines are not counted.
The test scripts themselves (scripts/test-*.sh) are not measured.

For Python: coverage.py's statement coverage of scripts/*.py, from
`coverage json`.

Traces hold the arguments of every command the tests run. Use this only on
tests (throwaway keys, stubs), never in a job that holds a real secret.

Standard library only (plus the shfmt binary for `report`).
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts"

# Every traced command starts with this (Bash repeats the leading "+" for
# each level of nesting): "+|coverage|<BASH_SOURCE>|<LINENO>| <command>".
TRACE_RE = re.compile(r"^\++\|coverage\|(?P<source>[^|\n]*)\|(?P<line>[0-9]+)\| ")

# Sourced by each Bash process through BASH_ENV. It does nothing unless the
# trace folder exists, so a command that clears the environment still runs.
BASH_ENV_FILE = r"""
if [ -n "${COVERAGE_TRACE_DIR-}" ] && [ -d "$COVERAGE_TRACE_DIR" ]; then
  exec {COVERAGE_TRACE_FD}>>"$COVERAGE_TRACE_DIR/trace.$$"
  BASH_XTRACEFD=$COVERAGE_TRACE_FD
  PS4='+|coverage|${BASH_SOURCE[0]-}|${LINENO}| '
  set -x
fi
"""

# The shfmt node types that are one command each (Bash traces each of them).
SIMPLE_COMMANDS = {
    "CallExpr",
    "DeclClause",
    "TestClause",
    "ArithmCmd",
    "LetClause",
    "TimeClause",
    "CoprocClause",
}


def measured_bash_files() -> list[Path]:
    files = [
        path
        for path in sorted(SCRIPTS_DIR.glob("*.sh"))
        if not path.name.startswith("test-")
    ]
    return files + sorted((SCRIPTS_DIR / "lib").glob("*.sh"))


def run(trace_dir: Path, command: list[str]) -> int:
    trace_dir.mkdir(parents=True, exist_ok=True)
    env_file = trace_dir / "bash-env.sh"
    env_file.write_text(BASH_ENV_FILE, encoding="utf-8")
    env = dict(os.environ)
    env["BASH_ENV"] = str(env_file.resolve())
    env["COVERAGE_TRACE_DIR"] = str(trace_dir.resolve())
    return subprocess.run(command, env=env, check=False).returncode


def command_ranges(node: object, out: list[tuple[int, int]]) -> None:
    """The first and last line of every simple command under the node."""
    if isinstance(node, list):
        for item in node:
            command_ranges(item, out)
        return
    if not isinstance(node, dict):
        return
    cmd = node.get("Cmd")
    is_statement = "Position" in node and isinstance(cmd, dict)
    if is_statement and cmd.get("Type") in SIMPLE_COMMANDS:
        out.append((node["Pos"]["Line"], node["End"]["Line"]))
        return
    for value in node.values():
        command_ranges(value, out)


def bash_lines(path: Path, shfmt: str) -> dict[int, set[int]]:
    """Each line any command covers -> the lines those commands start on."""
    parsed = subprocess.run(
        [shfmt, "-ln", "bash", "--to-json"],
        stdin=path.open("rb"),
        capture_output=True,
        check=False,
    )
    if parsed.returncode != 0:
        sys.exit(f"coverage.py: shfmt could not parse {path}: {parsed.stderr.decode()}")
    ranges: list[tuple[int, int]] = []
    command_ranges(json.loads(parsed.stdout), ranges)
    starts: dict[int, set[int]] = {}
    for first, last in ranges:
        for line in range(first, last + 1):
            starts.setdefault(line, set()).add(first)
    return starts


def traced_lines(trace_dir: Path, files: dict[Path, Path]) -> dict[Path, set[int]]:
    """For each measured file, the line numbers Bash traced in it."""
    traced: dict[Path, set[int]] = {path: set() for path in files.values()}
    cache: dict[str, Path | None] = {}
    for trace in sorted(trace_dir.glob("trace.*")):
        with trace.open(encoding="utf-8", errors="replace") as handle:
            for text in handle:
                match = TRACE_RE.match(text)
                if not match:
                    continue
                source = match["source"]
                if source not in cache:
                    candidate = Path(source)
                    if not candidate.is_absolute():
                        candidate = REPO_ROOT / candidate
                    cache[source] = files.get(Path(os.path.realpath(candidate)))
                path = cache[source]
                if path is not None:
                    traced[path].add(int(match["line"]))
    return traced


def ranges_text(lines: list[int]) -> str:
    """[1, 2, 3, 7] -> "1-3, 7"."""
    parts: list[str] = []
    start = previous = None
    for line in lines + [None]:
        if previous is not None and line == previous + 1:
            previous = line
            continue
        if start is not None:
            parts.append(str(start) if start == previous else f"{start}-{previous}")
        start = previous = line
    return ", ".join(parts)


def percent(covered: int, total: int) -> float:
    return 100.0 * covered / total if total else 100.0


def report(args: argparse.Namespace) -> int:
    files = {Path(os.path.realpath(path)): path for path in measured_bash_files()}
    traced = traced_lines(Path(args.trace_dir), files)
    summary: list[tuple[str, str, int, int]] = []

    print("Bash (lines that start a command):")
    bash_total = bash_covered = 0
    for path in files.values():
        starts = bash_lines(path, args.shfmt)
        executable = sorted({line for lines in starts.values() for line in lines})
        covered: set[int] = set()
        for line in traced[path]:
            covered |= starts.get(line, set())
        missing = [line for line in executable if line not in covered]
        name = str(path.relative_to(REPO_ROOT))
        bash_total += len(executable)
        bash_covered += len(covered)
        print(
            f"  {percent(len(covered), len(executable)):5.1f}%  "
            f"{len(covered):4}/{len(executable):<4}  {name}"
        )
        if missing:
            print(f"          not run: {ranges_text(missing)}")
        summary.append(("Bash", name, len(covered), len(executable)))
    print(
        f"  {percent(bash_covered, bash_total):5.1f}%  "
        f"{bash_covered:4}/{bash_total:<4}  Bash total"
    )

    python_total = python_covered = 0
    if args.python_json:
        data = json.loads(Path(args.python_json).read_text(encoding="utf-8"))
        print("Python (statements, coverage.py):")
        for name, entry in sorted(data["files"].items()):
            stats = entry["summary"]
            total, done = stats["num_statements"], stats["covered_lines"]
            python_total += total
            python_covered += done
            print(f"  {percent(done, total):5.1f}%  {done:4}/{total:<4}  {name}")
            if entry["missing_lines"]:
                print(
                    f"          not run: {ranges_text(sorted(entry['missing_lines']))}"
                )
            summary.append(("Python", name, done, total))
        print(
            f"  {percent(python_covered, python_total):5.1f}%  "
            f"{python_covered:4}/{python_total:<4}  Python total"
        )

    all_total = bash_total + python_total
    all_covered = bash_covered + python_covered
    print(f"Total: {percent(all_covered, all_total):.1f}% ({all_covered}/{all_total})")

    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as out:
            out.write(
                "## Coverage of scripts/\n\n| Language | File | Covered | % |\n|---|---|---|---|\n"
            )
            for language, name, done, total in summary:
                out.write(
                    f"| {language} | `{name}` | {done}/{total} | {percent(done, total):.1f} |\n"
                )
            out.write(
                f"| **Total** | | {all_covered}/{all_total} | "
                f"**{percent(all_covered, all_total):.1f}** |\n"
            )

    failures = []
    for what, done, total, floor in (
        ("Bash", bash_covered, bash_total, args.fail_under_bash),
        ("Python", python_covered, python_total, args.fail_under_python),
        ("total", all_covered, all_total, args.fail_under_total),
    ):
        if floor is not None and percent(done, total) < floor:
            failures.append(
                f"{what} coverage {percent(done, total):.1f}% is below {floor}%"
            )
    for failure in failures:
        print(f"coverage.py: {failure}", file=sys.stderr)
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="action", required=True)
    run_parser = sub.add_parser("run")
    run_parser.add_argument("trace_dir")
    run_parser.add_argument("command", nargs=argparse.REMAINDER)
    report_parser = sub.add_parser("report")
    report_parser.add_argument("trace_dir")
    report_parser.add_argument("--python-json")
    report_parser.add_argument("--shfmt", default="shfmt")
    for language in ("bash", "python", "total"):
        report_parser.add_argument(f"--fail-under-{language}", type=float)
    args = parser.parse_args()
    if args.action == "run":
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        if not command:
            parser.error("run: no command")
        return run(Path(args.trace_dir), command)
    return report(args)


if __name__ == "__main__":
    sys.exit(main())
