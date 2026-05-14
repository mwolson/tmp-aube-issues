#!/bin/bash
set -euo pipefail

if ! command -v aube >/dev/null 2>&1; then
    echo "aube is required" >&2
    exit 1
fi

rm -rf node_modules
aube install --fix-lockfile --ignore-scripts --reporter append-only

failures=0

if ! node <<'NODE'
const fs = require("fs");
const lock = JSON.parse(fs.readFileSync("package-lock.json", "utf8"));

if (lock.packages[""]?.dependencies?.["expo-router"] !== "~4.0.21") {
  console.error("failed: aube did not add the root expo-router dependency spec");
  process.exit(1);
}

if (!lock.packages["node_modules/expo-router"]) {
  console.error("failed: package-lock.json is missing packages[\"node_modules/expo-router\"]");
  process.exit(1);
}

console.log("pass: package-lock.json contains packages[\"node_modules/expo-router\"]");
NODE
then
    failures=1
fi

aube ci --ignore-scripts --reporter append-only

if [[ ! -e node_modules/expo-router ]]; then
    echo "failed: clean frozen install omitted node_modules/expo-router" >&2
    failures=1
else
    echo "pass: clean frozen install linked node_modules/expo-router"
fi

exit "$failures"
