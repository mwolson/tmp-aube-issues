#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
NPM_BIN="${NPM_BIN:-npm}"
for cmd in "$AUBE_BIN" "$NPM_BIN" node mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
if [[ "$("$NPM_BIN" --version)" != 11.6.2 ]]; then
    echo "use real npm 11.6.2 as NPM_BIN (the fixture's packageManager)" >&2
    exit 2
fi

cd "$(dirname "$0")"
mkdir -p "${REPRO_WORK_DIR:-$PWD/.repro-work}"
work=$(mktemp -d "${REPRO_WORK_DIR:-$PWD/.repro-work}/run.XXXXXX")
export AUBE_STORE_DIR="$work/aube-store" AUBE_CACHE_DIR="$work/aube-cache"
export AUBE_GLOBAL_VIRTUAL_STORE_DIR="$work/aube-gvs" npm_config_cache="$work/npm-cache"
aube_version=$("$AUBE_BIN" --version | head -n 1) || exit 2

# A new member joins the npm 11.6.2 workspace, then each tool updates the
# lockfile. Scenario `b`: the member has no dependencies. Scenario `c`: it has
# one dependency and declares os/cpu.
add_member() {
    mkdir -p "$1/$2"
    if [[ "$2" == b ]]; then
        printf '{\n  "name": "b",\n  "version": "1.0.0"\n}\n' > "$1/b/package.json"
    else
        cat > "$1/c/package.json" <<'EOF'
{
  "name": "c",
  "version": "1.0.0",
  "os": ["linux", "darwin", "win32"],
  "cpu": ["x64", "arm64"],
  "dependencies": {
    "is-number": "7.0.0"
  }
}
EOF
    fi
    node -e '
        const fs = require("fs"), file = process.argv[1], pkg = JSON.parse(fs.readFileSync(file));
        pkg.workspaces.push(process.argv[2]);
        fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + "\n");
    ' "$1/package.json" "$2"
}

entries() {
    node -e '
        const lock = JSON.parse(require("fs").readFileSync(process.argv[1])).packages;
        for (const key of [process.argv[2], "node_modules/" + process.argv[2]]) console.log(key + " " + JSON.stringify(lock[key] ?? null));
    ' "$1/package-lock.json" "$2"
}

failed=0
for member in b c; do
    for tool in npm aube; do
        dir="$work/$member-$tool"
        cp -r fixture "$dir"
        add_member "$dir" "$member"
        if [[ "$tool" == npm ]]; then
            (cd "$dir" && "$NPM_BIN" install --package-lock-only --ignore-scripts --no-audit --no-fund > install.log 2>&1) || {
                echo "npm control install failed: $dir/install.log" >&2
                exit 2
            }
        else
            (cd "$dir" && "$AUBE_BIN" install --ignore-scripts > install.log 2>&1) || {
                echo "aube install failed: $dir/install.log" >&2
                exit 1
            }
            rm -rf "${dir:?}/node_modules"
        fi
        entries "$dir" "$member" > "$dir/entries.txt"
        if (cd "$dir" && "$NPM_BIN" ci --ignore-scripts --no-audit --no-fund > ci.log 2>&1); then
            ci=pass
        else
            ci="FAIL: $(grep -m1 -o 'Missing: .* from lock file' "$dir/ci.log" || echo 'see ci.log')"
        fi
        echo "== member $member, $tool (npm ci: $ci)"
        sed 's/^/  /' "$dir/entries.txt"
        if [[ "$tool" == npm && "$ci" != pass ]]; then
            echo "npm control failed: $dir" >&2
            exit 2
        fi
        if [[ "$tool" == aube ]] && { [[ "$ci" != pass ]] || ! cmp -s "$work/$member-npm/entries.txt" "$dir/entries.txt"; }; then
            failed=1
        fi
    done
done

echo "aube: $aube_version; logs: $work"
if ((failed)); then
    echo "failed: aube's lockfile entries for a new workspace member differ from npm's" >&2
    exit 1
fi
echo "pass: new workspace members match npm and npm ci accepts the lockfile"
