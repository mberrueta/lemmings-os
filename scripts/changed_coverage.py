#!/usr/bin/env python3

import json
import subprocess
import sys
from pathlib import Path

BASE_REF = sys.argv[1] if len(sys.argv) > 1 else "origin/main...HEAD"


def run(cmd):
    return subprocess.check_output(cmd, text=True).strip()


changed = run([
    "git",
    "diff",
    "--name-only",
    BASE_REF,
    "--",
    "lib/**/*.ex",
]).splitlines()

changed = [p for p in changed if p]

if not changed:
    print("No changed lib/**/*.ex files found.")
    sys.exit(0)

print("Running coverage...")
subprocess.check_call([
    "bash",
    "-lc",
    "MIX_ENV=test mix coveralls.json",
])

coverage_path = Path("cover/excoveralls.json")

if not coverage_path.exists():
    print(f"Coverage file not found: {coverage_path}", file=sys.stderr)
    sys.exit(1)

data = json.loads(coverage_path.read_text())

source_files = data.get("source_files", [])

coverage_by_file = {}

for source in source_files:
    name = source.get("name") or source.get("filename")
    coverage = source.get("coverage", [])

    if not name:
        continue

    relevant = sum(1 for value in coverage if value is not None)
    missed = sum(1 for value in coverage if value == 0)
    covered = relevant - missed
    percent = 100.0 if relevant == 0 else covered * 100.0 / relevant

    coverage_by_file[name] = {
        "percent": percent,
        "relevant": relevant,
        "missed": missed,
        "covered": covered,
    }


rows = []
for path in changed:
    stats = coverage_by_file.get(path)
    rows.append((path, stats))

rows.sort(
    key=lambda row: (
        0 if row[1] is not None else 1,
        -(row[1]["percent"] if row[1] is not None else -1),
        row[0],
    )
)

print()
print("Changed-file coverage")
print("---------------------")

total_relevant = 0
total_missed = 0

for path, stats in rows:
    if stats is None:
        print(f"MISS  {path}  not present in coverage output")
        continue

    total_relevant += stats["relevant"]
    total_missed += stats["missed"]

    print(
        f"{stats['percent']:6.1f}%  "
        f"{path}  "
        f"relevant={stats['relevant']}  "
        f"missed={stats['missed']}"
    )

print("---------------------")

if total_relevant == 0:
    total_percent = 100.0
else:
    total_percent = (total_relevant - total_missed) * 100.0 / total_relevant

print(
    f"TOTAL {total_percent:6.1f}%  "
    f"relevant={total_relevant}  "
    f"missed={total_missed}"
)
