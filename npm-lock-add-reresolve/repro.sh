#!/bin/bash
set -euo pipefail

# aube add re-resolves unrelated versions in a fresh npm package-lock.json.
#
# package.json pins jest-config@29.7.0 exactly. The checked-in lockfile is one
# npm can produce and accept:
#
#   npm 11.17.0 install --ignore-scripts --package-lock-only --no-audit --no-fund
#
# npm 12.0.2 install --package-lock-only left that lock byte-identical.
# npm hoists camelcase@5.3.1 (for @istanbuljs/load-nyc-config) and nests
# camelcase@6.3.0 under jest-validate.
#
# aube install treats the lock as fresh. aube add is-number@7.0.0 (already a
# transitive) and aube add jest-config@29.7.0 (already the exact pin) both
# hoist camelcase to 6.3.0. Real npm only promotes the named spec. The same
# rewrite happens with aube install --fix-lockfile, and with either isolated
# or hoisted AUBE_NODE_LINKER.

AUBE_BIN="${AUBE_BIN:-aube}"

resolve_real_npm() {
    if [[ -n "${NPM_BIN:-}" ]]; then
        printf '%s\n' "$NPM_BIN"
        return
    fi
    local candidate
    for candidate in \
        "${AUBESHIM_REAL_NPM:-}" \
        "${HOME}/.local/share/mise/installs/node/lts/bin/npm" \
        /usr/bin/npm
    do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    command -v npm
}

camelcase_version() {
    node -e '
        const fs = require("fs");
        const lock = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        process.stdout.write(String(lock.packages["node_modules/camelcase"]?.version || ""));
    ' "$1"
}

for cmd in "$AUBE_BIN" node; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

if ! NPM_BIN="$(resolve_real_npm)"; then
    echo "missing real npm (set NPM_BIN or AUBESHIM_REAL_NPM)" >&2
    exit 2
fi

if "$NPM_BIN" --version 2>/dev/null | grep -qi aubeshim; then
    echo "NPM_BIN resolves to the aubeshim shim; point it at a real npm binary" >&2
    exit 2
fi

cd "$(dirname "$0")"

AUBE_VERSION="$("$AUBE_BIN" --version 2>/dev/null | head -n 1 || true)"
NPM_VERSION="$("$NPM_BIN" --version 2>/dev/null | tail -n 1 || true)"
echo "aube: ${AUBE_VERSION}"
echo "real npm: ${NPM_VERSION} (${NPM_BIN})"

BASE_CAMEL="$(camelcase_version package-lock.json)"
if [[ "$BASE_CAMEL" != "5.3.1" ]]; then
    echo "expected checked-in lock to hoist camelcase@5.3.1, got ${BASE_CAMEL:-none}" >&2
    exit 2
fi

WORK=.repro-work
rm -rf "$WORK"
mkdir "$WORK"
cp package.json package-lock.json "$WORK/"
cd "$WORK"

if ! "$NPM_BIN" install --ignore-scripts --package-lock-only --no-audit --no-fund; then
    echo "npm could not accept the checked-in package-lock.json" >&2
    exit 2
fi
NPM_ACCEPT_CAMEL="$(camelcase_version package-lock.json)"
if [[ "$NPM_ACCEPT_CAMEL" != "5.3.1" ]]; then
    echo "npm package-lock-only changed hoisted camelcase (${BASE_CAMEL} -> ${NPM_ACCEPT_CAMEL})" >&2
    exit 2
fi

if ! "$AUBE_BIN" install --ignore-scripts --reporter append-only; then
    echo "aube install failed" >&2
    exit 2
fi
INSTALL_CAMEL="$(camelcase_version package-lock.json)"
if [[ "$INSTALL_CAMEL" != "5.3.1" ]]; then
    echo "aube install rewrote hoisted camelcase (${BASE_CAMEL} -> ${INSTALL_CAMEL})" >&2
    exit 1
fi

cp ../package.json ../package-lock.json .
if ! "$NPM_BIN" install is-number@7.0.0 --ignore-scripts --package-lock-only --no-audit --no-fund; then
    echo "npm install is-number@7.0.0 failed" >&2
    exit 2
fi
NPM_ADD_CAMEL="$(camelcase_version package-lock.json)"
if [[ "$NPM_ADD_CAMEL" != "5.3.1" ]]; then
    echo "control failed: npm install is-number@7.0.0 changed camelcase to ${NPM_ADD_CAMEL}" >&2
    exit 2
fi
echo "pass: npm install is-number@7.0.0 kept camelcase@${NPM_ADD_CAMEL}"

cp ../package.json ../package-lock.json .
if ! "$AUBE_BIN" add is-number@7.0.0 --ignore-scripts --reporter append-only; then
    echo "aube add is-number@7.0.0 failed" >&2
    exit 2
fi
AUBE_ADD_CAMEL="$(camelcase_version package-lock.json)"
if [[ "$AUBE_ADD_CAMEL" != "5.3.1" ]]; then
    echo "aube add is-number@7.0.0 re-resolved hoisted camelcase (${BASE_CAMEL} -> ${AUBE_ADD_CAMEL})" >&2
    exit 1
fi

echo "pass: aube add is-number@7.0.0 kept camelcase@${AUBE_ADD_CAMEL}"
