#!/bin/bash
set -euo pipefail

for cmd in aube node; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd" >&2
        exit 2
    fi
done

cd "$(dirname "$0")"

unset FORCE_COLOR CLICOLOR_FORCE CI
export NO_COLOR=1

resolve_pnpm() {
    local candidate
    for candidate in "${PNPM_BIN:-}" "${AUBESHIM_REAL_PNPM:-}"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    if command -v mise >/dev/null 2>&1; then
        candidate="$(mise which pnpm 2>/dev/null || true)"
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi
    if command -v pnpm >/dev/null 2>&1; then
        command -v pnpm
        return 0
    fi
    return 1
}

PNPM_BIN="$(resolve_pnpm || true)"
if [[ -n "$PNPM_BIN" ]] && "$PNPM_BIN" --version 2>/dev/null | grep -q aubeshim; then
    echo "PNPM_BIN resolves to the aubeshim shim; point it at a real pnpm binary" >&2
    exit 2
fi

echo "aube: $(aube --version 2>/dev/null | head -1)"
echo "node: $(node --version)"
if [[ -n "$PNPM_BIN" ]]; then
    echo "pnpm: $("$PNPM_BIN" --version 2>/dev/null | head -1) ($PNPM_BIN)"
else
    echo "pnpm: (not found; native comparison skipped)"
fi

work_dir=".repro-work"
rm -rf "$work_dir"
mkdir -p "$work_dir/project" "$work_dir/xdg-cache" "$work_dir/xdg-config"
: >"$work_dir/empty-npmrc"
cp package.json index.js metro.config.js resolve-with-metro.js "$work_dir/project/"

export XDG_CACHE_HOME="$PWD/$work_dir/xdg-cache"
export XDG_CONFIG_HOME="$PWD/$work_dir/xdg-config"
export NPM_CONFIG_USERCONFIG="$PWD/$work_dir/empty-npmrc"

project_dir="$PWD/$work_dir/project"
cd "$project_dir"

print_layout() {
    local label="$1"
    echo
    echo "=== $label ==="
    node -e '
const fs = require("fs");
const path = require("path");
const local = path.resolve("node_modules/is-number");
const exists = fs.existsSync(local);
const isLink = exists && fs.lstatSync(local).isSymbolicLink();
let real = null;
if (exists) {
  real = fs.realpathSync(local);
}
const projectRoot = process.cwd();
console.log("local:", local);
console.log("exists:", exists, "islink:", isLink);
if (isLink) {
  console.log("readlink:", fs.readlinkSync(local));
}
console.log("realpath:", real);
console.log("realpath inside project:", Boolean(real && real.startsWith(projectRoot + path.sep)));
try {
  console.log("node resolve:", require.resolve("is-number"));
} catch (error) {
  console.log("node resolve: ERROR", error.message);
}
'
}

clean_modules() {
    rm -rf node_modules aube-lock.yaml pnpm-lock.yaml package-lock.json .metro-cache
}

run_metro() {
    local out="$1"
    shift
    set +e
    env "$@" node resolve-with-metro.js >"$out" 2>&1
    local status=$?
    set -e
    if grep -q "RESULT: OK" "$out"; then
        echo "metro: OK"
        return 0
    fi
    if grep -q "RESULT: FAIL" "$out"; then
        echo "metro: FAIL"
        grep -E "Unable to resolve|  /" "$out" | head -20
        return 1
    fi
    echo "metro: unexpected output (exit $status)" >&2
    tail -n 40 "$out" >&2
    return 2
}

is_number_real() {
    node -e 'console.log(require("fs").realpathSync(require("path").dirname(require.resolve("is-number/package.json"))))'
}

echo
echo "=== explicit GVS override (known-incompatible control) ==="
clean_modules
aube install --node-linker=isolated --enable-global-virtual-store --ignore-scripts --no-frozen-lockfile --reporter append-only
print_layout "isolated + explicit GVS"
if ! node -e 'require.resolve("is-number"); require.resolve("is-number/package.json")'; then
    echo "setup failed: Node could not resolve is-number after the GVS install" >&2
    exit 2
fi
gvs_real="$(is_number_real)"
if [[ "$gvs_real" == "$project_dir"* ]]; then
    echo "setup failed: explicit GVS install kept is-number inside the project ($gvs_real)" >&2
    exit 2
fi
if run_metro explicit-gvs.out; then
    echo "setup failed: Metro unexpectedly resolved through the explicitly enabled GVS" >&2
    exit 2
fi

echo
echo "=== extraNodeModules realpath without watchFolders ==="
if run_metro extra-node-modules.out METRO_EXTRA_NODE_MODULES="is-number=$gvs_real"; then
    echo "setup failed: extraNodeModules alone unexpectedly resolved is-number" >&2
    exit 2
fi

echo
echo "=== watchFolders includes package realpath ==="
if ! run_metro watch-folders.out METRO_WATCH_FOLDERS="$gvs_real"; then
    echo "setup failed: watchFolders of the GVS package realpath did not fix Metro" >&2
    exit 2
fi

echo
echo "=== aube isolated + disable GVS ==="
clean_modules
aube install --node-linker=isolated --disable-global-virtual-store --ignore-scripts --reporter append-only
print_layout "isolated without GVS"
if ! run_metro disable-gvs.out; then
    echo "setup failed: Metro still failed after disabling the global virtual store" >&2
    exit 2
fi

echo
echo "=== aube hoisted (AUBE_NODE_LINKER=hoisted) ==="
clean_modules
AUBE_NODE_LINKER=hoisted aube install --enable-global-virtual-store --ignore-scripts --reporter append-only
print_layout "hoisted layout"
if ! run_metro hoisted.out; then
    echo "setup failed: Metro failed after a hoisted aube install" >&2
    exit 2
fi

if [[ -n "$PNPM_BIN" ]]; then
    echo
    echo "=== native pnpm isolated ==="
    clean_modules
    "$PNPM_BIN" install --ignore-scripts --config.node-linker=isolated
    print_layout "native pnpm isolated"
    if ! run_metro pnpm-isolated.out; then
        echo "setup failed: Metro failed after native pnpm isolated install" >&2
        exit 2
    fi
fi

echo
echo "=== default aube install (case under test) ==="
clean_modules
aube install --node-linker=isolated --ignore-scripts --reporter append-only 2>&1 | tee default-install.out
print_layout "default isolated layout"
if ! grep -q "WARN_AUBE_GVS_INCOMPATIBLE" default-install.out; then
    echo "failed: aube did not report that it disabled GVS for the Metro project" >&2
    exit 1
fi
default_real="$(is_number_real)"
if [[ "$default_real" != "$project_dir"* ]]; then
    echo "failed: default Metro install kept is-number outside the project ($default_real)" >&2
    exit 1
fi
if ! run_metro default-case.out; then
    echo "failed: Metro could not resolve after aube's default compatibility detection" >&2
    exit 1
fi

echo
echo "pass: aube disabled GVS for the Metro project and Metro resolved is-number"
exit 0
