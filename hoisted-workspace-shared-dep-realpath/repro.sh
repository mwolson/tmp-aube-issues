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

clean_modules() {
    rm -rf node_modules packages/app/node_modules packages/lib/node_modules
}

# Package-root identity via Node resolution from each importer.
# After the hoisted workspace-wide plan fix, packages/*/node_modules/is-number
# may be intentionally absent (both importers resolve up to root node_modules).
# Comparing require.resolve realpaths is the stable assertion either way.
print_layout() {
    local label="$1"
    echo "=== $label ==="
    echo "aube: $(aube --version 2>/dev/null | head -1)"
    node -e '
const fs = require("fs");
const path = require("path");

const importers = ["packages/app", "packages/lib"];
const results = [];

for (const importer of importers) {
  const local = path.join(importer, "node_modules", "is-number");
  const localExists = fs.existsSync(local);
  let resolved = null;
  let real = null;
  let err = null;
  try {
    resolved = require.resolve("is-number", { paths: [path.resolve(importer)] });
    real = fs.realpathSync(path.dirname(resolved));
  } catch (e) {
    err = e.message;
  }
  results.push({ importer, local, localExists, resolved, real, err });
  console.log(`${importer}:`);
  console.log(`  local path: ${local}`);
  console.log(`  local exists: ${localExists}${localExists ? ` islink=${fs.lstatSync(local).isSymbolicLink()}` : ""}`);
  if (err) {
    console.log(`  resolve: ERROR ${err}`);
  } else {
    console.log(`  resolve: ${resolved}`);
    console.log(`  package realpath: ${real}`);
  }
}

const reals = results.map((r) => r.real).filter(Boolean);
if (reals.length === 2) {
  console.log(`same resolve realpath: ${reals[0] === reals[1]}`);
} else {
  console.log("same resolve realpath: false (resolve failed for one or both importers)");
}
'
}

resolved_same() {
    node -e '
const fs = require("fs");
const path = require("path");
function pkgReal(importer) {
  const resolved = require.resolve("is-number", { paths: [path.resolve(importer)] });
  return fs.realpathSync(path.dirname(resolved));
}
try {
  const a = pkgReal("packages/app");
  const b = pkgReal("packages/lib");
  process.stdout.write(a === b ? "true" : "false");
} catch {
  process.stdout.write("false");
}
'
}

# Baseline: isolated should share one physical instance via resolution.
clean_modules
aube install --node-linker=isolated --ignore-scripts --reporter append-only
print_layout "isolated"
isolated_same="$(resolved_same)"
if [[ "$isolated_same" != "true" ]]; then
    echo "setup failed: isolated install did not share is-number resolve realpath" >&2
    exit 2
fi

# Case under test: hoisted should share one package-root realpath across
# workspace importers (pnpm-compatible). Pre-fix aube planned separate trees
# per importer; post-fix both resolve to the same root placement.
clean_modules
aube install --node-linker=hoisted --ignore-scripts --reporter append-only
print_layout "hoisted"

hoisted_same="$(resolved_same)"

if [[ "$hoisted_same" == "true" ]]; then
    echo "pass: hoisted install shares is-number resolve realpath across workspace packages"
    exit 0
fi

echo "failed: hoisted install resolves is-number to distinct realpaths per workspace package" >&2
echo "expected: same require.resolve realpath from each importer (may be root node_modules)" >&2
exit 1
