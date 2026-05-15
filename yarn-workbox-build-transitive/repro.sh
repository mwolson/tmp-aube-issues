#!/bin/bash
set -euo pipefail

YARN_BIN="${YARN_BIN:-yarn}"

for cmd in aube node "$YARN_BIN"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

yarn_version_output="$("$YARN_BIN" --version)"
if [[ "$yarn_version_output" == *"shimmed by aubeshim"* ]]; then
    echo "YARN_BIN must point to a real Yarn binary, not the aubeshim yarn shim" >&2
    exit 2
fi

yarn_version="${yarn_version_output%%$'\n'*}"
if [[ "$yarn_version" != 1.* ]]; then
    echo "YARN_BIN must point to Yarn classic v1; got $yarn_version" >&2
    exit 2
fi

cd "$(dirname "$0")"

check_workbox_transitive() {
    node <<'NODE'
const validateOptions = require.resolve("workbox-build/build/lib/validate-options.js");
require.resolve("@apideck/better-ajv-errors", { paths: [validateOptions] });
NODE
}

rm -rf node_modules
"$YARN_BIN" install --frozen-lockfile --ignore-scripts
if ! check_workbox_transitive; then
    echo "native Yarn did not make workbox-build's declared dependency resolvable" >&2
    exit 2
fi

rm -rf node_modules
aube install --frozen-lockfile --ignore-scripts --reporter append-only
if ! check_workbox_transitive; then
    echo "aube did not make workbox-build's declared dependency resolvable" >&2
    exit 1
fi
