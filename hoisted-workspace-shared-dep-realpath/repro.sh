#!/bin/bash
set -euo pipefail

if ! command -v aube >/dev/null 2>&1; then
    echo "aube is required" >&2
    exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required" >&2
    exit 2
fi

cd "$(dirname "$0")"

clean_modules() {
    rm -rf node_modules packages/app/node_modules packages/lib/node_modules
}

print_layout() {
    local label="$1"
    echo "=== $label ==="
    echo "aube: $(aube --version 2>/dev/null | head -1)"
    python3 - <<'PY'
import os
from pathlib import Path

pairs = [
    ("packages/app/node_modules/is-number", "packages/lib/node_modules/is-number"),
]
for a, b in pairs:
    pa, pb = Path(a), Path(b)
    if not pa.exists() or not pb.exists():
        print(f"missing: {a} exists={pa.exists()} {b} exists={pb.exists()}")
        continue
    ra, rb = os.path.realpath(a), os.path.realpath(b)
    print(f"app  is-number: path={a}")
    print(f"      realpath={ra}")
    print(f"      islink={os.path.islink(a)} isdir={pa.is_dir()}")
    print(f"lib  is-number: path={b}")
    print(f"      realpath={rb}")
    print(f"      islink={os.path.islink(b)} isdir={pb.is_dir()}")
    print(f"same realpath: {ra == rb}")
PY
}

# Baseline: isolated should share one physical instance.
clean_modules
aube install --node-linker=isolated --ignore-scripts --reporter append-only
print_layout "isolated"
isolated_same="$(python3 - <<'PY'
import os
print(os.path.realpath("packages/app/node_modules/is-number") ==
      os.path.realpath("packages/lib/node_modules/is-number"))
PY
)"
if [[ "$isolated_same" != "True" ]]; then
    echo "setup failed: isolated install did not share is-number realpath" >&2
    exit 2
fi

# Case under test: hoisted materializes separate real directories per workspace.
clean_modules
aube install --node-linker=hoisted --ignore-scripts --reporter append-only
print_layout "hoisted"

hoisted_same="$(python3 - <<'PY'
import os
print(os.path.realpath("packages/app/node_modules/is-number") ==
      os.path.realpath("packages/lib/node_modules/is-number"))
PY
)"

if [[ "$hoisted_same" == "True" ]]; then
    echo "pass: hoisted install shares is-number realpath across workspace packages"
    exit 0
fi

echo "failed: hoisted install uses distinct is-number realpaths per workspace package" >&2
echo "expected: same realpath (hardlink/symlink to one store-backed tree)" >&2
exit 1
