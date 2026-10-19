#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
NPM_BIN="${NPM_BIN:-npm}"

for cmd in "$AUBE_BIN" "$NPM_BIN" node tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

if "$NPM_BIN" --version 2>/dev/null | grep -q aubeshim; then
    echo "NPM_BIN resolves to the aubeshim shim; point it at a real npm binary" >&2
    exit 2
fi

cd "$(dirname "$0")"
work="$PWD/.repro-work"

# fixture/lib holds lib/index.js and lib/__tests__/index.test.js.
variants=(
    'negated-recursive|["lib", "!**/__tests__"]'
    'negated-path|["lib", "!lib/__tests__"]'
    'dir-double-star|["lib/**"]'
)

setup() {
    local name=$1 files=$2
    local dir="$work/$name"
    mkdir -p "$dir/out"
    cp -r fixture/. "$dir/"
    printf '{\n  "name": "pack-files-glob",\n  "version": "1.0.0",\n  "files": %s\n}\n' \
        "$files" >"$dir/package.json"
}

npm_files() {
    (cd "$1" && "$NPM_BIN" pack --dry-run --json 2>/dev/null) |
        node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s)[0].files.map(f=>f.path).sort().join(" ")))'
}

aube_files() {
    local dir=$1
    if ! (cd "$dir" && "$AUBE_BIN" pack --pack-destination out >"$dir.log" 2>&1); then
        echo "error: $(grep -m1 'files glob' "$dir.log" | sed 's/^[^a-z]*//')"
        return
    fi
    tar tzf "$dir"/out/*.tgz | sed 's|^package/||' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}

rm -rf "$work"
fail=0
for variant in "${variants[@]}"; do
    name=${variant%%|*}
    files=${variant#*|}
    setup "$name" "$files"
    expected="$(npm_files "$work/$name")"
    if [[ -z "$expected" ]]; then
        echo "control failed: npm pack --dry-run produced no file list for $name" >&2
        exit 2
    fi
    actual="$(aube_files "$work/$name")"
    echo "$name files=$files"
    echo "  npm $("$NPM_BIN" --version): $expected"
    echo "  aube: $actual"
    if [[ "$actual" != "$expected" ]]; then
        fail=1
    fi
done

if ((fail)); then
    echo "failed: aube pack does not select the same files as npm pack" >&2
    exit 1
fi
echo "pass: aube pack matches npm pack for every files pattern"
