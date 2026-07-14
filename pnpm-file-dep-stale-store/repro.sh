#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"

for cmd in "$AUBE_BIN" node "$PNPM_BIN"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

if "$PNPM_BIN" --version 2>/dev/null | grep -q aubeshim; then
    echo "PNPM_BIN resolves to the aubeshim shim; point it at a real pnpm binary" >&2
    exit 2
fi

cd "$(dirname "$0")"
root="$(pwd)"

# Fixture files restored into a disposable work dir so the committed
# source stays at marker=v1 while the script mutates the copy.
setup() {
    rm -rf .repro-work
    mkdir -p .repro-work
    cp package.json pnpm-workspace.yaml .repro-work/
    cp -r packages .repro-work/
}

read_marker() {
    # Resolve from the app package so both aube's virtual-store hardlink
    # tree and pnpm's store copy are what require() actually sees.
    (
        cd packages/app
        node -e '
const path = require("path");
const fs = require("fs");
const pkgJson = require.resolve("@repro/local-mod/package.json");
const root = path.dirname(pkgJson);
const js = fs.readFileSync(path.join(root, "index.js"), "utf8");
const m = js.match(/marker:\s*"([^"]+)"/);
if (!m) process.exit(2);
process.stdout.write(m[1] + "\n" + root + "\n");
'
    )
}

marker_value() {
    read_marker | sed -n '1p' | tr -d '\r'
}

marker_path() {
    read_marker | sed -n '2p'
}

mutate_source() {
    cat > packages/app/modules/local-mod/index.js <<'JS'
module.exports = { marker: "v2" };
JS
    cat > packages/app/modules/local-mod/index.d.ts <<'TS'
export declare const marker: "v2";
TS
}

run_install() {
    local bin="$1"
    # CI=1 matches the observed session (frozen lockfile defaults etc.).
    # --no-frozen-lockfile is not needed; manifests and lock stay in sync.
    if [[ "$(basename "$bin")" == aube ]]; then
        CI=1 "$bin" install --ignore-scripts --reporter append-only
    else
        CI=1 "$bin" install --ignore-scripts
    fi
}

# Settle aube's warm path: the first install materializes, a second pass
# often rewrites lock/state (seen as local-mod@0.0.0), and a third pass
# takes the warm path ("Already up to date" with the default reporter;
# append-only is silent). The bug is that a later install after the
# file: source mutates still takes that warm path and keeps the stale
# store copy.
settle_aube() {
    run_install "$AUBE_BIN" >/dev/null
    run_install "$AUBE_BIN" >/dev/null
    run_install "$AUBE_BIN" >/dev/null
}

echo "=== native pnpm parity ==="
setup
cd .repro-work
run_install "$PNPM_BIN" >/dev/null
# Second install so pnpm is past the cold path, matching a warm tree.
run_install "$PNPM_BIN" >/dev/null
m1="$(marker_value)"
if [[ "$m1" != "v1" ]]; then
    echo "native pnpm initial install did not link marker=v1 (got $m1)" >&2
    exit 2
fi
echo "native pnpm after settle: marker=$m1"
echo "  path=$(marker_path)"
mutate_source
echo "mutated source to marker=v2"
set +e
out_pnpm="$(run_install "$PNPM_BIN" 2>&1)"
pnpm_rc=$?
set -e
echo "$out_pnpm" | tail -n 15
m2="$(marker_value || true)"
echo "native pnpm after re-install: marker=${m2:-<unreadable>}"
pnpm_stale=0
if [[ "$m2" != "v2" ]]; then
    pnpm_stale=1
    echo "native pnpm kept stale installed copy (marker=$m2, expected v2, install_rc=$pnpm_rc)"
else
    echo "native pnpm refreshed the file: dep to marker=v2"
fi
cd "$root"

echo
echo "=== aube ==="
setup
cd .repro-work
settle_aube
m1="$(marker_value)"
if [[ "$m1" != "v1" ]]; then
    echo "aube settled install did not link marker=v1 (got $m1)" >&2
    exit 2
fi
echo "aube after settle: marker=$m1"
echo "  path=$(marker_path)"
if [[ -d node_modules/.aube ]]; then
    echo "aube store entries:"
    ls -1 node_modules/.aube
fi
mutate_source
echo "mutated source to marker=v2"
set +e
out_aube="$(run_install "$AUBE_BIN" 2>&1)"
aube_rc=$?
set -e
echo "$out_aube" | tail -n 15
m2="$(marker_value || true)"
echo "aube after re-install: marker=${m2:-<unreadable>}"
aube_stale=0
if [[ "$m2" != "v2" ]]; then
    aube_stale=1
    echo "aube kept stale installed copy (marker=$m2, expected v2, install_rc=$aube_rc)"
else
    echo "aube refreshed the file: dep to marker=v2"
fi

if [[ "$aube_stale" -eq 1 ]]; then
    echo
    echo "=== aube workaround: wipe file: store entry and reinstall ==="
    find node_modules/.aube -maxdepth 1 -type d -name '*@repro+local-mod@file+*' \
        -exec rm -rf {} + 2>/dev/null || true
    run_install "$AUBE_BIN" >/dev/null
    m3="$(marker_value || true)"
    echo "aube after store wipe + reinstall: marker=${m3:-<unreadable>}"
    if [[ "$m3" != "v2" ]]; then
        echo "workaround did not refresh either" >&2
    fi
fi

echo
echo "matrix: native_pnpm_stale=$pnpm_stale aube_stale=$aube_stale"

if [[ "$aube_stale" -eq 0 ]]; then
    echo "pass: aube refreshed file: dep content on reinstall"
    exit 0
fi

if [[ "$pnpm_stale" -eq 1 ]]; then
    echo "observed: aube and native pnpm both kept a stale file: store copy"
    exit 1
fi

echo "observed: aube kept a stale file: store copy; native pnpm refreshed"
exit 1
