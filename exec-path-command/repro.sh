#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"
for cmd in "$AUBE_BIN" "$PNPM_BIN" bash cp ls node; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
if "$PNPM_BIN" --version | grep -q aubeshim; then
    echo "PNPM_BIN must point at real pnpm, not aubeshim" >&2
    exit 2
fi
AUBE_BIN=$(command -v "$AUBE_BIN")
PNPM_BIN=$(command -v "$PNPM_BIN")
cd "$(dirname "$0")"
work="$PWD/.repro-work"
rm -rf "${work:?}"
mkdir -p "$work"
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"
export XDG_CACHE_HOME="$work/xdg-cache" XDG_DATA_HOME="$work/xdg-data"
export XDG_STATE_HOME="$work/xdg-state"
export AUBE_NO_AUTO_INSTALL=true
unset CI
cp -r fixture "$work/project"
cd "$work/project"
mkdir -p node_modules/.bin
printf '#!/bin/sh\nprintf "project-bin-ok\\n"\n' > node_modules/.bin/project-probe
chmod +x node_modules/.bin/project-probe

for bin in "$PNPM_BIN" "$AUBE_BIN"; do
    if ! "$bin" exec project-probe >"$work/$(basename "$bin")-local.log" 2>&1; then
        echo "local bin setup failed for $bin" >&2
        exit 2
    fi
    if ! "$bin" run probe >"$work/$(basename "$bin")-script.log" 2>&1; then
        echo "package script could not run node for $bin" >&2
        exit 2
    fi
done

failed=
check() {
    local label=$1
    shift
    if ! "$PNPM_BIN" "$@" >"$work/$label-pnpm.log" 2>&1; then
        echo "control failed: pnpm $* (see $work/$label-pnpm.log)" >&2
        exit 2
    fi
    if "$AUBE_BIN" "$@" >"$work/$label-aube.log" 2>&1; then
        if cmp -s "$work/$label-pnpm.log" "$work/$label-aube.log"; then
            echo "pass: $*"
        else
            echo "failed: output differs for $* (see $work/$label-aube.log)"
            failed=true
        fi
    else
        echo "failed: aube $*"
        cat "$work/$label-aube.log"
        failed=true
    fi
}

echo "aube: $("$AUBE_BIN" --version | head -1)"
echo "pnpm control: $("$PNPM_BIN" --version); node: $(node --version)"
check node-flags exec node -p process.version
check separator exec -- node -p process.version
check ls exec ls package.json
check bash exec -- bash -c 'printf bash-ok'
check recursive -r exec node -p process.version
check filtered --filter exec-member exec node -p process.version
if [[ -n "$failed" ]]; then
    exit 1
fi
echo "pass: project bins and commands on PATH both run"
