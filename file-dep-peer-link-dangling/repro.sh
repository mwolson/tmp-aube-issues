#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
PNPM_BIN="${PNPM_BIN:-pnpm}"

for cmd in "$AUBE_BIN" "$PNPM_BIN" node; do
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
work="$PWD/.repro-work"
rm -rf "$work"
pnpm_version=$("$PNPM_BIN" --version)
aube_version=$("$AUBE_BIN" --version)

# Keep every store and cache inside .repro-work. A shared global virtual store
# can hide the bug: its entry for the peer link is keyed by the file: path, so
# a stale entry from another project with the same relative path may resolve.
export AUBE_STORE_DIR="$work/aube-store"
export pnpm_config_store_dir="$work/pnpm-store" pnpm_config_cache_dir="$work/pnpm-cache"

# fixture: workspace member app depends on react from file:deps/react and on
# use-sync-external-store@1.5.0, which declares react as a peer. The member
# keeps the root node_modules free of react, so nothing up the tree masks a
# broken peer link.
seed="$work/seed"
mkdir -p "$seed"
cp -r fixture/. "$seed/"
if ! (cd "$seed" && "$PNPM_BIN" install --lockfile-only --ignore-scripts >"$seed.log" 2>&1); then
    echo "control failed: pnpm could not write the seed lockfile (see $seed.log)" >&2
    exit 2
fi

# Print the react that use-sync-external-store resolves, or why it cannot.
peer_react() {
    node -e '
        const fs = require("fs"), path = require("path");
        const pkg = fs.realpathSync(path.join(process.argv[1], "app/node_modules/use-sync-external-store"));
        const link = path.join(path.dirname(pkg), "react");
        let target = "";
        try { target = fs.readlinkSync(link); } catch {}
        try {
            const found = require(require.resolve("react", { paths: [pkg] }));
            console.log(found.local ? "file:deps/react" : "a different react");
        } catch {
            console.log("not resolvable" + (target ? " (dangling link -> " + target + ")" : ""));
        }
    ' "$1"
}

dir="$work/pnpm"
cp -r "$seed" "$dir"
(cd "$dir" && "$PNPM_BIN" install --frozen-lockfile --ignore-scripts >"$dir.log" 2>&1)
pnpm_result=$(peer_react "$dir")
echo "pnpm $pnpm_version: use-sync-external-store resolves react to $pnpm_result"
if [[ "$pnpm_result" != file:deps/react ]]; then
    echo "control failed: pnpm did not link the file: react as the peer" >&2
    exit 2
fi

failed=
for mode in default --disable-global-virtual-store; do
    dir="$work/aube$mode"
    cp -r "$seed" "$dir"
    flags=(--frozen-lockfile)
    [[ "$mode" == default ]] || flags+=("$mode")
    if ! (cd "$dir" && AUBE_CACHE_DIR="$dir-cache" "$AUBE_BIN" install "${flags[@]}" >"$dir.log" 2>&1); then
        echo "aube install ${flags[*]} failed (see $dir.log)" >&2
        exit 2
    fi
    result=$(peer_react "$dir")
    echo "aube $aube_version install ${flags[*]}: use-sync-external-store resolves react to $result"
    [[ "$result" == file:deps/react ]] || failed=1
done

if [[ -n "$failed" ]]; then
    echo "failed: aube links a file: dependency that satisfies a peer under a name it never creates" >&2
    exit 1
fi
echo "pass: aube links the file: dependency that satisfies the peer"
