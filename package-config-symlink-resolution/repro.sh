#!/bin/bash
set -euo pipefail

aube_bin=${AUBE_BIN:-aube}

for cmd in "$aube_bin" node tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd" >&2
        exit 2
    fi
done

echo "aube: $("$aube_bin" --version)"
echo "node: $(node --version)"

cd "$(dirname "$0")"

# An ancestor node_modules/is-number would satisfy the symlink-path require and
# hide the issue, so treat that as an environment problem.
dir=$(cd .. && pwd)
while [[ "$dir" != / ]]; do
    if [[ -e "$dir/node_modules/is-number" ]]; then
        echo "environment: $dir/node_modules/is-number is reachable from this case" >&2
        exit 2
    fi
    dir=$(dirname "$dir")
done

rm -rf node_modules aube-lock.yaml package-lock.json packages/config-owner-1.0.0.tgz .tmp

mkdir -p .tmp/package
cp packages/config-owner/package.json packages/config-owner/react-native.config.js .tmp/package/
tar -czf packages/config-owner-1.0.0.tgz -C .tmp package

"$aube_bin" install

node scripts/load-config.cjs
