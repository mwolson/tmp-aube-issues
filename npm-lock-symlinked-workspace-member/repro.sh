#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
NPM_BIN="${NPM_BIN:-npm}"
for cmd in "$AUBE_BIN" "$NPM_BIN" node mktemp cmp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
if [[ "$("$NPM_BIN" --version)" != 11.6.2 ]]; then
    echo "use real npm 11.6.2 as NPM_BIN (the npm that wrote the fixtures)" >&2
    exit 2
fi

cd "$(dirname "$0")"
mkdir -p "${REPRO_WORK_DIR:-$PWD/.repro-work}"
work=$(mktemp -d "${REPRO_WORK_DIR:-$PWD/.repro-work}/run.XXXXXX")
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export AUBE_GLOBAL_VIRTUAL_STORE_DIR="$work/aube-gvs" npm_config_cache="$work/npm-cache"
aube_version=$("$AUBE_BIN" --version | head -n 1) || exit 2
npm_flags=(--ignore-scripts --no-audit --no-fund)

# Three lockfiles npm 11.6.2 wrote with an entry outside node_modules that is
# not an installed package:
# - symlinked: workspace member packages/b is a symlink to ../../ext/b, and
#   npm adds "../ext/b": {"version": "1.0.0", "extraneous": true}.
# - removed: member packages/b was deleted, and npm keeps
#   "packages/b": {"version": "1.0.0", "extraneous": true}.
# - delisted-parent: packages/b left `workspaces` while its subfolder
#   packages/b/inner stayed a member, and npm keeps "packages/b":
#   {"version": "1.0.0"} without the extraneous flag.
# Each project then gets a frozen install, and is-number@7.0.0 is added to the
# root with each tool so the rewritten lockfiles can be compared.
setup() {
    cp -r "fixture/$1" "$2"
    if [[ "$1" == symlinked ]]; then
        mkdir "$2/root/packages"
        ln -s ../../ext/b "$2/root/packages/b"
    fi
}

project() {
    if [[ "$1" == symlinked ]]; then echo "$2/root"; else echo "$2"; fi
}

failed=0
for scenario in symlinked removed delisted-parent; do
    echo "== $scenario"

    dir="$work/$scenario-npm-ci"
    setup "$scenario" "$dir"
    root=$(project "$scenario" "$dir")
    cp "$root/package-lock.json" "$dir.lock"
    (cd "$root" && "$NPM_BIN" ci "${npm_flags[@]}" > "$dir.log" 2>&1) &&
        cmp -s "$dir.lock" "$root/package-lock.json" || {
        echo "npm control: npm ci failed or changed the lockfile: $dir.log" >&2
        exit 2
    }
    echo "  npm ci: pass, lockfile unchanged"

    dir="$work/$scenario-aube-frozen"
    setup "$scenario" "$dir"
    root=$(project "$scenario" "$dir")
    cp "$root/package-lock.json" "$dir.lock"
    if (cd "$root" && "$AUBE_BIN" install --frozen-lockfile --ignore-scripts > "$dir.log" 2>&1); then
        if ! cmp -s "$dir.lock" "$root/package-lock.json"; then
            echo "  aube install --frozen-lockfile: passed but changed the lockfile"
            failed=1
        elif [[ "$scenario" == symlinked ]] &&
            ! (cd "$root" && node -e 'require("b/package.json")' > /dev/null 2>&1); then
            echo "  aube install --frozen-lockfile: passed but require('b') fails from the root"
            failed=1
        else
            echo "  aube install --frozen-lockfile: pass, lockfile unchanged"
        fi
    else
        echo "  aube install --frozen-lockfile: FAIL"
        sed -n '1,12p' "$dir.log" | sed 's/^/    /'
        failed=1
    fi

    dir="$work/$scenario-npm-add"
    setup "$scenario" "$dir"
    npm_root=$(project "$scenario" "$dir")
    (cd "$npm_root" && "$NPM_BIN" install --save-exact "${npm_flags[@]}" is-number@7.0.0 > "$dir.log" 2>&1) || {
        echo "npm control: npm install is-number@7.0.0 failed: $dir.log" >&2
        exit 2
    }
    dir="$work/$scenario-aube-add"
    setup "$scenario" "$dir"
    aube_root=$(project "$scenario" "$dir")
    if ! (cd "$aube_root" && "$AUBE_BIN" add -W --save-exact --ignore-scripts is-number@7.0.0 > "$dir.log" 2>&1); then
        echo "  aube add is-number@7.0.0: FAIL"
        sed -n '1,12p' "$dir.log" | sed 's/^/    /'
        failed=1
    elif diff -u "$npm_root/package-lock.json" "$aube_root/package-lock.json" > "$work/$scenario-add.diff"; then
        echo "  aube add is-number@7.0.0: lockfile identical to npm 11.6.2"
    else
        echo "  aube add is-number@7.0.0: lockfile differs from npm 11.6.2"
        sed 's/^/    /' "$work/$scenario-add.diff"
        failed=1
    fi
done

echo "aube: $aube_version; logs: $work"
if ((failed)); then
    echo "failed: aube cannot install or round-trip npm's entries outside node_modules" >&2
    exit 1
fi
echo "pass: aube installs and round-trips npm's entries outside node_modules"
