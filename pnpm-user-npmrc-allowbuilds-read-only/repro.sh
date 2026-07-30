#!/bin/bash
set -euo pipefail

# `aube config get allowBuilds` used to report a value from the user-level
# `~/.npmrc` that `aube install` then ignored.
#
# The install path only consults project-scoped sources
# (`package.json#aube.allowBuilds` / `package.json#pnpm.allowBuilds` and
# workspace yaml). Reporting a user `.npmrc` value made the documented way to
# check the setting confirm a configuration that had no effect.
#
# Acceptable outcomes (either is a fix):
#   1. `config get` does not report the unsupported `.npmrc` source, or
#   2. install honors the value that `config get` reports.
#
# Fixed in aube 1.35.0 via #1159 (outcome 1).
#
# Runs entirely inside a throwaway HOME, so the real `~/.npmrc` is untouched.
# Point AUBE_BIN at a real aube binary when HOME redirection breaks mise shims.

AUBE_BIN="${AUBE_BIN:-aube}"

for cmd in "$AUBE_BIN" node; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

cd "$(dirname "$0")"

WORK="$(mktemp -d)"
FAKE_HOME="${WORK}/home"
PROJECT="${WORK}/project"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$FAKE_HOME" "$PROJECT"
cp package.json "$PROJECT/"

printf 'allowBuilds={"esbuild":true}\n' > "${FAKE_HOME}/.npmrc"

cd "$PROJECT"

reported="$(HOME="$FAKE_HOME" "$AUBE_BIN" config get allowBuilds 2>/dev/null || true)"
reports_npmrc=0
if grep -q 'esbuild' <<<"$reported"; then
    reports_npmrc=1
fi

HOME="$FAKE_HOME" "$AUBE_BIN" install >/dev/null 2>&1 || true
ignored="$(HOME="$FAKE_HOME" "$AUBE_BIN" ignored-builds 2>/dev/null || true)"
install_ignored=0
if grep -q 'esbuild' <<<"$ignored"; then
    install_ignored=1
fi

# Control: the same allowlist in package.json#aube.allowBuilds is honored,
# which is what makes the divergence a source-specific issue rather than an
# unsupported setting.
rm -rf node_modules
node -e '
const fs = require("node:fs");
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
pkg.aube = { allowBuilds: { esbuild: true } };
fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
'
HOME="$FAKE_HOME" "$AUBE_BIN" install >/dev/null 2>&1 || true
ignored_pkg="$(HOME="$FAKE_HOME" "$AUBE_BIN" ignored-builds 2>/dev/null || true)"
if grep -q 'esbuild' <<<"$ignored_pkg"; then
    echo "control failed: package.json#aube.allowBuilds was also ignored, so this is not a source-specific divergence" >&2
    exit 2
fi

if [[ "$reports_npmrc" -eq 1 && "$install_ignored" -eq 1 ]]; then
    echo "aube config get reported allowBuilds=${reported} from ~/.npmrc, but install still skipped the build:" >&2
    echo "${ignored}" | sed 's/^/    /' >&2
    exit 1
fi

if [[ "$reports_npmrc" -eq 0 ]]; then
    echo "pass: aube config get no longer reports allowBuilds from ~/.npmrc (install ignores that source by design)"
    exit 0
fi

echo "pass: aube install honored the allowBuilds value that config get reported"
