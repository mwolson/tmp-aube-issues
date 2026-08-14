#!/bin/bash
set -euo pipefail

if ! command -v aube >/dev/null 2>&1; then
    echo "aube is required" >&2
    exit 2
fi

if ! command -v node >/dev/null 2>&1; then
    echo "node is required" >&2
    exit 2
fi

cd "$(dirname "$0")"

work_dir=".repro-work"
rm -rf "$work_dir"
mkdir -p "$work_dir/packages/app"
cp package.json pnpm-workspace.yaml "$work_dir/"
cp packages/app/package.json "$work_dir/packages/app/"
cd "$work_dir"

# Agent and some user shells set FORCE_COLOR / CLICOLOR_FORCE. aube then
# paints "+ is-number@7.0.0" and "installed 1 package" with ANSI, which
# would make a literal output check miss a real reinstall.
unset FORCE_COLOR CLICOLOR_FORCE
export NO_COLOR=1

echo "aube: $(aube --version 2>/dev/null | head -1)"

aube install --node-linker=hoisted --ignore-scripts --reporter append-only

echo
echo "=== hoisted layout ==="
echo "root is-number exists: $([[ -e node_modules/is-number ]] && echo yes || echo no)"
echo "package-local is-number exists: $([[ -e packages/app/node_modules/is-number ]] && echo yes || echo no)"

node -e '
const fs = require("fs");
const path = require("path");
const importer = path.resolve("packages/app");
const local = path.join(importer, "node_modules", "is-number");
if (fs.existsSync(local)) {
  console.error("setup failed: package-local is-number exists; hoisted root-only placement is required");
  process.exit(2);
}
const resolved = require.resolve("is-number", { paths: [importer] });
const real = fs.realpathSync(path.dirname(resolved));
const root = fs.realpathSync(path.resolve("node_modules/is-number"));
console.log("resolve from packages/app:", resolved);
console.log("package realpath:", real);
if (real !== root) {
  console.error("setup failed: packages/app did not resolve is-number through the root hoisted placement");
  process.exit(2);
}
'

missing_reason="installed entry missing: packages/app/node_modules/is-number"

run_ok() {
    local label="$1"
    shift
    local out="$1"
    shift
    echo
    echo "=== $label ==="
    echo "command: $*"
    set +e
    "$@" >"$out" 2>&1
    local status=$?
    set -e
    cat "$out"
    if [[ "$status" -ne 0 ]]; then
        echo "setup failed: command exited $status" >&2
        exit 2
    fi
}

plain_text() {
    # Strip CSI sequences so install proof is not color-dependent.
    sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' "$1"
}

is_false_positive() {
    local out="$1"
    local text
    text="$(plain_text "$out")"
    grep -Fq "Auto-installing: $missing_reason" <<<"$text" || return 1
    grep -Eq '(\+ is-number@7\.0\.0|installed 1 package)' <<<"$text"
}

run_ok "aube run ok (1)" run1.out aube run ok
run_ok "aube run ok (2)" run2.out aube run ok
run_ok "AUBE_NO_AUTO_INSTALL=1 aube run ok" control.out env AUBE_NO_AUTO_INSTALL=1 aube run ok

if grep -q "Auto-installing:" control.out; then
    echo "setup failed: AUBE_NO_AUTO_INSTALL=1 still auto-installed" >&2
    exit 2
fi

if is_false_positive run1.out && is_false_positive run2.out; then
    echo
    echo "failed: hoisted auto-install treated the absent package-local slot as missing twice" >&2
    echo "expected: aube run ok stays warm after a valid hoisted install" >&2
    exit 1
fi

if is_false_positive run1.out || is_false_positive run2.out; then
    echo "setup failed: only one of the two aube run invocations reinstalled" >&2
    exit 2
fi

echo
echo "pass: hoisted auto-install stayed warm for the root-only is-number placement"
exit 0
