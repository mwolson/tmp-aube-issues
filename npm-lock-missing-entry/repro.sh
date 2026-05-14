#!/bin/bash
set -euo pipefail

if ! command -v aube >/dev/null 2>&1; then
    echo "aube is required" >&2
    exit 1
fi

rm -rf node_modules
aube install --fix-lockfile --ignore-scripts --reporter append-only

node <<'NODE'
const fs = require("fs");
const lock = JSON.parse(fs.readFileSync("package-lock.json", "utf8"));

if (lock.packages[""]?.dependencies?.["expo-router"] !== "~4.0.21") {
  console.error("expected aube to add the root expo-router dependency spec");
  process.exit(1);
}

if (lock.packages["node_modules/expo-router"]) {
  console.error("bug not reproduced: package-lock.json contains node_modules/expo-router");
  process.exit(1);
}

console.log("reproduced: package-lock.json is missing packages[\"node_modules/expo-router\"]");
NODE

aube ci --ignore-scripts --reporter append-only

if [[ -e node_modules/expo-router ]]; then
    echo "bug not reproduced: clean frozen install linked expo-router" >&2
    exit 1
fi

echo "reproduced: clean frozen install omitted node_modules/expo-router"
