#!/bin/bash
set -euo pipefail

for cmd in aube node tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd" >&2
        exit 2
    fi
done

echo "aube: $(aube --version)"
echo "node: $(node --version)"

cd "$(dirname "$0")"

rm -rf node_modules aube-lock.yaml package-lock.json packages/config-owner-1.0.0.tgz .tmp

mkdir -p .tmp/package
cp packages/config-owner/package.json packages/config-owner/react-native.config.js .tmp/package/
tar -czf packages/config-owner-1.0.0.tgz -C .tmp package

aube install

node scripts/load-config.cjs
