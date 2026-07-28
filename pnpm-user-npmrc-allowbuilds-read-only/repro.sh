#!/bin/bash
set -euo pipefail

# `aube config get allowBuilds` reports a value from the user-level `~/.npmrc`
# that `aube install` then ignores.
#
# The read path treats `~/.npmrc` as a valid source for `allowBuilds`, so
# querying the setting confirms the package is allowed. The install path only
# consults `package.json#aube.allowBuilds` and workspace yaml, so the build is
# still skipped and reported by `aube ignored-builds`.
#
# Either source should be honored, or `config get` should not report a value
# from a location the install ignores. As it stands, the documented way to check
# the setting actively confirms a configuration that has no effect.
#
# Follow-up to the write half of this, raised in discussion #617: `aube config
# set allowBuilds.<pkg> true` used to write to `~/.npmrc` with no effect. That
# path now errors with ERR_AUBE_CONFIG_NESTED_AUBE_KEY. The read path was not
# changed with it.
#
# Runs entirely inside a throwaway HOME, so the real `~/.npmrc` is untouched.

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

# 1. The read path reports the user-level value.
reported="$(HOME="$FAKE_HOME" "$AUBE_BIN" config get allowBuilds 2>/dev/null || true)"
if ! grep -q 'esbuild' <<<"$reported"; then
    echo "expected 'aube config get allowBuilds' to report the ~/.npmrc value, got: ${reported:-<empty>}" >&2
    echo "the read path may have changed; this repro is stale" >&2
    exit 2
fi

# 2. The install path ignores it.
HOME="$FAKE_HOME" "$AUBE_BIN" install >/dev/null 2>&1 || true
ignored="$(HOME="$FAKE_HOME" "$AUBE_BIN" ignored-builds 2>/dev/null || true)"

fail=0
if grep -q 'esbuild' <<<"$ignored"; then
    echo "aube config get reported allowBuilds=${reported} from ~/.npmrc, but install still skipped the build:" >&2
    echo "${ignored}" | sed 's/^/    /' >&2
    fail=1
fi

# 3. Control: the same allowlist in package.json#aube.allowBuilds is honored,
#    which is what makes the divergence a read/write inconsistency rather than
#    an unsupported setting.
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

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "pass: aube install honored the allowBuilds value that config get reported"
