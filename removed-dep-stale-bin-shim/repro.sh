#!/bin/bash
set -euo pipefail

AUBE_BIN="${AUBE_BIN:-aube}"
for cmd in "$AUBE_BIN" cp mktemp node tee; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done
AUBE_BIN="$(command -v "$AUBE_BIN")"
AUBE_BIN="$(node -e 'process.stdout.write(require("path").resolve(process.argv[1]))' "$AUBE_BIN")"

main() {
    cd "$(dirname "$0")"
    local fixture="$PWD"
    mkdir -p tmp
    local work
    work="$(mktemp -d "$fixture/tmp/run.XXXXXX")"
    echo "aube: $("$AUBE_BIN" --version)"
    echo "node: $(node --version)"
    echo "work: $work"
    mkdir -p "$work/path-bin"
    cat > "$work/path-bin/semver" <<'SH'
#!/bin/sh
echo PATH-fallback
SH
    chmod +x "$work/path-bin/semver"
    export PATH="$work/path-bin:$PATH"
    export AUBE_MODULES_CACHE_MAX_AGE=10080
    export AUBE_NODE_LINKER=isolated
    export AUBE_PREFER_SYMLINKED_EXECUTABLES=false
    local failures=0 mode removal
    for mode in true false; do
        export AUBE_ENABLE_GLOBAL_VIRTUAL_STORE="$mode"
        for removal in remove manifest pulled-lockfile; do
            run_case "$fixture" "$work" "$mode" "$removal"
        done
    done
    echo
    echo "matrix: $failures/6 cases retained a removed dependency's bin"
    [[ "$failures" -eq 0 ]]
}

run_case() {
    local fixture="$1" work="$2" mode="$3" removal="$4"
    local project="$work/gvs-$mode-$removal"
    mkdir -p "$project"
    cd "$project"
    cp "$fixture/package.json" .
    echo
    echo "=== global virtual store=$mode, removal=$removal ==="
    "$AUBE_BIN" install 2>&1 | tee initial-install.log || exit 2
    if [[ "$(node_modules/.bin/semver 1.2.3)" != "1.2.3" ]]; then
        echo "initial semver binary did not work" >&2
        exit 2
    fi
    node -e '
const fs = require("fs");
const linked = fs.lstatSync("node_modules/.aube/semver@7.7.2").isSymbolicLink();
if (linked !== (process.env.AUBE_ENABLE_GLOBAL_VIRTUAL_STORE === "true")) {
    throw new Error("requested virtual-store mode was not applied");
}
if (!fs.lstatSync("node_modules/.bin/semver").isFile()) {
    throw new Error("expected a regular-file bin shim");
}
' || exit 2
    node -e '
const fs = require("fs");
const old = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000);
fs.lutimesSync("node_modules/.aube/semver@7.7.2", old, old);
' || exit 2
    echo "aged semver virtual-store entry by 8 days (default cache retention is 7 days)"
    case "$removal" in
        remove)
            "$AUBE_BIN" remove semver 2>&1 | tee removal.log || exit 2
            ;;
        manifest)
            remove_manifest_dep
            "$AUBE_BIN" install 2>&1 | tee removal.log || exit 2
            ;;
        pulled-lockfile)
            mkdir updated
            cp package.json aube-lock.yaml updated/
            (
                cd updated
                remove_manifest_dep
                "$AUBE_BIN" install --lockfile-only
            ) 2>&1 | tee lockfile-generation.log || exit 2
            cp updated/package.json updated/aube-lock.yaml .
            "$AUBE_BIN" install 2>&1 | tee removal.log || exit 2
            ;;
    esac
    node -e '
const fs = require("fs");
const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
if (p.devDependencies?.semver || fs.readFileSync("aube-lock.yaml", "utf8").includes("semver")) {
    throw new Error("semver was not removed from both manifest and lockfile");
}
' || exit 2
    local failed=0
    if ! inspect_bin "after removal"; then
        failed=1
    fi
    "$AUBE_BIN" install 2>&1 | tee follow-up-install.log || exit 2
    if ! inspect_bin "after follow-up install"; then
        failed=1
    fi
    local output run_status=0
    output="$("$AUBE_BIN" run check 2>&1)" || run_status=$?
    printf '%s\n' "$output" | tee run-check.log
    echo "aube run check exit=$run_status (expected 0 and PATH-fallback)"
    if [[ "$run_status" -ne 0 || "$output" != *PATH-fallback* ]]; then
        failed=1
    fi
    if [[ "$failed" -ne 0 ]]; then
        "$AUBE_BIN" install --force 2>&1 | tee force-install.log || exit 2
        inspect_bin "after force install" || true
        "$AUBE_BIN" prune 2>&1 | tee prune.log || exit 2
        inspect_bin "after prune" || true
        "$AUBE_BIN" ci 2>&1 | tee ci.log || exit 2
        if ! inspect_bin "after clean install"; then
            echo "clean-install control did not remove the shim" >&2
            exit 2
        fi
        run_status=0
        output="$("$AUBE_BIN" run check 2>&1)" || run_status=$?
        printf '%s\n' "$output" | tee run-after-ci.log
        if [[ "$run_status" -ne 0 || "$output" != *PATH-fallback* ]]; then
            echo "clean-install control did not restore PATH fallback" >&2
            exit 2
        fi
        failures=$((failures + 1))
    else
        echo "pass: removed bin is absent and aube run uses PATH fallback"
    fi
}

remove_manifest_dep() {
    node -e '
const fs = require("fs");
const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
delete p.devDependencies.semver;
fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");
'
}

inspect_bin() {
    local label="$1"
    if [[ -e node_modules/.bin/semver || -L node_modules/.bin/semver ]]; then
        echo "FAIL $label: node_modules/.bin/semver survives"
        if [[ -e node_modules/.aube/semver@7.7.2/node_modules/semver/bin/semver.js ]]; then
            echo "  target: present (removed package also survives)"
        else
            echo "  target: absent (dangling shim)"
        fi
        return 1
    fi
    echo "PASS $label: node_modules/.bin/semver is absent"
}

main "$@"
