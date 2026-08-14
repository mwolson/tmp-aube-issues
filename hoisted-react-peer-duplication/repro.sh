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
    rm -rf node_modules packages/web/node_modules packages/mobile/node_modules
}

print_layout() {
    local label="$1"
    echo "=== $label ==="
    echo "aube: $(aube --version 2>/dev/null | head -1)"
    node -e '
const fs = require("fs");
const path = require("path");

function pkgReal(resolved) {
  let dir = path.dirname(resolved);
  for (let i = 0; i < 5; i++) {
    if (fs.existsSync(path.join(dir, "package.json"))) {
      return fs.realpathSync(dir);
    }
    dir = path.dirname(dir);
  }
  return fs.realpathSync(path.dirname(resolved));
}

function resolveReact(fromDir) {
  const resolved = require.resolve("react", { paths: [path.resolve(fromDir)] });
  const real = pkgReal(resolved);
  const ver = JSON.parse(fs.readFileSync(path.join(real, "package.json"), "utf8")).version;
  return { resolved, real, ver };
}

const web = resolveReact("packages/web");
const zustandDir = fs.existsSync("node_modules/zustand")
  ? "node_modules/zustand"
  : "packages/web/node_modules/zustand";
const zustand = resolveReact(zustandDir);
const mobile = resolveReact("packages/mobile");

console.log("web react:", web.ver, web.real);
console.log("zustand react:", zustand.ver, zustand.real);
console.log("mobile react:", mobile.ver, mobile.real);
console.log("web vs zustand same realpath:", web.real === zustand.real);
console.log("web vs zustand same export:", require(web.resolved) === require(zustand.resolved));

const placements = "node_modules/.aube-state/hoisted-placements.json";
if (fs.existsSync(placements)) {
  console.log("hoisted-placements.json:", fs.readFileSync(placements, "utf8").trim());
}
'
}

same_web_zustand() {
    node -e '
const fs = require("fs");
const path = require("path");

function pkgReal(resolved) {
  let dir = path.dirname(resolved);
  for (let i = 0; i < 5; i++) {
    if (fs.existsSync(path.join(dir, "package.json"))) {
      return fs.realpathSync(dir);
    }
    dir = path.dirname(dir);
  }
  return fs.realpathSync(path.dirname(resolved));
}

try {
  const web = pkgReal(require.resolve("react", { paths: [path.resolve("packages/web")] }));
  const zustandDir = fs.existsSync("node_modules/zustand")
    ? "node_modules/zustand"
    : "packages/web/node_modules/zustand";
  const zustand = pkgReal(require.resolve("react", { paths: [path.resolve(zustandDir)] }));
  process.stdout.write(web === zustand ? "true" : "false");
} catch {
  process.stdout.write("false");
}
'
}

# Baseline: isolated should give web and zustand the same React identity.
clean_modules
aube install --node-linker=isolated --ignore-scripts --reporter append-only
print_layout "isolated"
isolated_same="$(same_web_zustand)"
if [[ "$isolated_same" != "true" ]]; then
    echo "setup failed: isolated install did not share React realpath between web and zustand" >&2
    exit 2
fi

# Case under test: hoisted should still share one react@19.2.6 package-root
# realpath between the web importer and the hoisted zustand peer package.
# Native pnpm 11.21.0 hoisted does that by placing 19.2.6 at the workspace
# root. Pre-fix aube 1.40.0 lets packages/mobile claim root with 19.2.3, then
# materializes 19.2.6 twice (web local + zustand nest).
clean_modules
aube install --node-linker=hoisted --ignore-scripts --reporter append-only
print_layout "hoisted"

hoisted_same="$(same_web_zustand)"

if [[ "$hoisted_same" == "true" ]]; then
    echo "pass: hoisted install shares React resolve realpath between web and zustand"
    exit 0
fi

echo "failed: hoisted install resolves React to distinct realpaths for web and zustand" >&2
echo "expected: one react@19.2.6 package-root realpath from packages/web and from zustand" >&2
exit 1
