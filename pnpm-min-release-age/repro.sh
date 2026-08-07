#!/bin/bash
set -euo pipefail

# aube vs native pnpm: minimumReleaseAge / lockfile age verification parity.
#
# pnpm 11 defaults minimumReleaseAge to 1440 minutes and re-verifies lockfile
# entries on install (ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION when a pinned
# version is too young). aube documents the same 1440 default, but:
#   1) resolve-time age is non-strict by default (installs a young exact pin
#      when no mature candidate exists), and
#   2) installs from an existing lockfile do not re-verify published age.
#
# This repro uses a local mock registry that always reports publishedAt=now so
# the case stays durable without relying on a same-day public npm publish.
#
# Exit 0 = aube matches pnpm (both reject). Exit 1 = gap observed.
# Exit 2 = missing tools / setup failure.

AUBE_BIN="${AUBE_BIN:-aube}"
# Prefer an explicit real pnpm. AUBESHIM_REAL_PNPM is the aubeshim escape hatch;
# mise installs are checked next so PATH shims do not resolve to aubeshim.
resolve_real_pnpm() {
    if [[ -n "${PNPM_BIN:-}" ]]; then
        printf '%s\n' "$PNPM_BIN"
        return
    fi
    if [[ -n "${AUBESHIM_REAL_PNPM:-}" ]]; then
        printf '%s\n' "$AUBESHIM_REAL_PNPM"
        return
    fi
    local candidate
    for candidate in \
        "${HOME}/.local/share/mise/installs/pnpm/latest/pnpm" \
        "${HOME}/.local/share/mise/installs/pnpm/11/pnpm" \
        "${HOME}/.local/share/mise/installs/pnpm/11.20.0/pnpm"
    do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    # Last resort: PATH entry that is not the aubeshim shim.
    if command -v pnpm >/dev/null 2>&1; then
        candidate="$(command -v pnpm)"
        if ! "$candidate" --version 2>/dev/null | grep -qi aubeshim; then
            printf '%s\n' "$candidate"
            return
        fi
    fi
    return 1
}

for cmd in "$AUBE_BIN" node; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

if ! PNPM_BIN="$(resolve_real_pnpm)"; then
    echo "missing real pnpm (set PNPM_BIN or AUBESHIM_REAL_PNPM)" >&2
    exit 2
fi

if "$PNPM_BIN" --version 2>/dev/null | grep -qi aubeshim; then
    echo "PNPM_BIN resolves to the aubeshim shim; point it at a real pnpm binary" >&2
    exit 2
fi

cd "$(dirname "$0")"
ROOT="$(pwd)"

AUBE_VERSION="$("$AUBE_BIN" --version 2>/dev/null | head -n 1 || true)"
PNPM_VERSION="$("$PNPM_BIN" --version 2>/dev/null | head -n 1 || true)"
AUBESHIM_VERSION=""
if command -v aubeshim >/dev/null 2>&1; then
    AUBESHIM_VERSION="$(aubeshim --version 2>/dev/null | head -n 1 || true)"
fi

echo "aube: ${AUBE_VERSION}"
echo "real pnpm: ${PNPM_VERSION} (${PNPM_BIN})"
if [[ -n "$AUBESHIM_VERSION" ]]; then
    echo "aubeshim: ${AUBESHIM_VERSION}"
fi
echo

WORK="${ROOT}/.repro-work"
rm -rf "$WORK"
mkdir -p "$WORK/registry" "$WORK/project" "$WORK/logs"

# Pack the fixture with npm's pack (bypass aubeshim npm shim when possible).
resolve_real_npm() {
    if [[ -n "${NPM_BIN:-}" ]]; then
        printf '%s\n' "$NPM_BIN"
        return
    fi
    local candidate
    for candidate in \
        "${HOME}/.local/share/mise/installs/node/lts/bin/npm" \
        "${HOME}/.local/share/mise/installs/node/lts-krypton/bin/npm"
    do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    # Any npm is fine for packing a local directory.
    command -v npm
}

NPM_BIN="$(resolve_real_npm)"
(
    cd "$ROOT/fixture/fresh-pkg"
    "$NPM_BIN" pack --silent --pack-destination "$WORK/registry" >/dev/null
)

TARBALL="$WORK/registry/fresh-pkg-1.0.0.tgz"
if [[ ! -f "$TARBALL" ]]; then
    echo "failed to pack fixture tarball" >&2
    exit 2
fi

read -r INTEGRITY SHASUM < <(
    node -e '
const fs = require("fs");
const crypto = require("crypto");
const b = fs.readFileSync(process.argv[1]);
const integrity = "sha512-" + crypto.createHash("sha512").update(b).digest("base64");
const shasum = crypto.createHash("sha1").update(b).digest("hex");
process.stdout.write(integrity + " " + shasum + "\n");
' "$TARBALL"
)

# Start mock registry; it writes the bound port to PORT_FILE.
REG_LOG="$WORK/logs/registry.log"
PORT_FILE="$WORK/registry.port"
rm -f "$PORT_FILE"
PORT=0 \
TARBALL_PATH="$TARBALL" \
TARBALL_INTEGRITY="$INTEGRITY" \
TARBALL_SHASUM="$SHASUM" \
PORT_FILE="$PORT_FILE" \
    node "$ROOT/mock-registry.mjs" >"$REG_LOG" 2>&1 &
REG_PID=$!

cleanup() {
    if [[ -n "${REG_PID:-}" ]]; then
        kill "$REG_PID" 2>/dev/null || true
        wait "$REG_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Wait for the port file.
for _ in $(seq 1 50); do
    if [[ -s "$PORT_FILE" ]]; then
        break
    fi
    if ! kill -0 "$REG_PID" 2>/dev/null; then
        echo "mock registry exited early:" >&2
        cat "$REG_LOG" >&2 || true
        exit 2
    fi
    sleep 0.05
done

if [[ ! -s "$PORT_FILE" ]]; then
    echo "mock registry did not report a port" >&2
    cat "$REG_LOG" >&2 || true
    exit 2
fi

REG_PORT="$(tr -d '[:space:]' <"$PORT_FILE")"
REG_URL="http://127.0.0.1:${REG_PORT}/"
echo "mock registry: ${REG_URL}"

# Smoke the packument.
if ! curl -fsS "${REG_URL}fresh-pkg" >/dev/null; then
    echo "mock registry smoke request failed" >&2
    cat "$REG_LOG" >&2 || true
    exit 2
fi

write_project() {
    local age_minutes="$1"
    mkdir -p "$WORK/project"
    cat >"$WORK/project/package.json" <<'EOF'
{
  "name": "pnpm-min-release-age-repro",
  "private": true,
  "dependencies": {
    "fresh-pkg": "1.0.0"
  }
}
EOF
    cat >"$WORK/project/pnpm-workspace.yaml" <<EOF
# Explicit so both tools share the same gate (pnpm 11 default is also 1440).
minimumReleaseAge: ${age_minutes}
EOF
    cat >"$WORK/project/.npmrc" <<EOF
registry=${REG_URL}
EOF
}

run_pnpm() {
    local label="$1"
    local out="$WORK/logs/pnpm-${label}.out"
    set +e
    (
        cd "$WORK/project"
        "$PNPM_BIN" install --ignore-scripts
    ) >"$out" 2>&1
    local rc=$?
    set -e
    echo "$rc" >"$WORK/logs/pnpm-${label}.rc"
    echo "--- native pnpm (${label}) rc=${rc} ---"
    # Strip noisy Node NO_COLOR warnings.
    grep -v 'NO_COLOR' "$out" | tail -n 30 || true
    return 0
}

run_aube() {
    local label="$1"
    local out="$WORK/logs/aube-${label}.out"
    set +e
    (
        cd "$WORK/project"
        "$AUBE_BIN" install --ignore-scripts --reporter append-only
    ) >"$out" 2>&1
    local rc=$?
    set -e
    echo "$rc" >"$WORK/logs/aube-${label}.rc"
    echo "--- aube (${label}) rc=${rc} ---"
    grep -v 'NO_COLOR' "$out" | tail -n 40 || true
    return 0
}

fresh_pkg_linked() {
    [[ -e "$WORK/project/node_modules/fresh-pkg" || -L "$WORK/project/node_modules/fresh-pkg" ]]
}

########################################################################
# Scenario A: lockfile supply-chain verification (matches original report)
# 1. Build a lockfile with minimumReleaseAge: 0 (young pin allowed).
# 2. Flip to minimumReleaseAge: 1440 and reinstall from that lock.
# Native pnpm should fail with ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION.
# aube should still install.
########################################################################

echo "=== scenario A: lockfile age verification ==="
write_project 0
rm -rf "$WORK/project/node_modules" \
    "$WORK/project/pnpm-lock.yaml" \
    "$WORK/project/aube-lock.yaml"
run_pnpm "seed-lock"
if [[ ! -f "$WORK/project/pnpm-lock.yaml" ]]; then
    echo "failed to seed pnpm-lock.yaml with minimumReleaseAge: 0" >&2
    cat "$WORK/logs/pnpm-seed-lock.out" >&2 || true
    exit 2
fi
cp "$WORK/project/pnpm-lock.yaml" "$WORK/logs/pnpm-lock-young.yaml"

# Flip age gate on; keep the young lock.
write_project 1440
cp "$WORK/logs/pnpm-lock-young.yaml" "$WORK/project/pnpm-lock.yaml"
rm -rf "$WORK/project/node_modules" "$WORK/project/aube-lock.yaml"
run_pnpm "lock-verify"
PNPM_LOCK_RC="$(cat "$WORK/logs/pnpm-lock-verify.rc")"
PNPM_LOCK_REJECTED=0
if grep -q 'ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION\|ERR_PNPM_NO_MATURE_MATCHING_VERSION' \
    "$WORK/logs/pnpm-lock-verify.out"
then
    PNPM_LOCK_REJECTED=1
fi
# pnpm may still materialize packages before failing; treat any age error as reject.
if [[ "$PNPM_LOCK_RC" -ne 0 ]]; then
    PNPM_LOCK_REJECTED=1
fi

rm -rf "$WORK/project/node_modules" "$WORK/project/aube-lock.yaml"
cp "$WORK/logs/pnpm-lock-young.yaml" "$WORK/project/pnpm-lock.yaml"
run_aube "lock-verify"
AUBE_LOCK_RC="$(cat "$WORK/logs/aube-lock-verify.rc")"
AUBE_LOCK_INSTALLED=0
if [[ "$AUBE_LOCK_RC" -eq 0 ]] && fresh_pkg_linked; then
    AUBE_LOCK_INSTALLED=1
fi

echo
echo "scenario A matrix: pnpm_rejected=${PNPM_LOCK_REJECTED} aube_installed=${AUBE_LOCK_INSTALLED}"

########################################################################
# Scenario B: cold resolve of a young exact pin under minimumReleaseAge 1440.
# Native pnpm: ERR_PNPM_NO_MATURE_MATCHING_VERSION.
# aube (default non-strict): installs the young pin.
########################################################################

echo
echo "=== scenario B: cold resolve of young exact pin ==="
write_project 1440
rm -rf "$WORK/project/node_modules" \
    "$WORK/project/pnpm-lock.yaml" \
    "$WORK/project/aube-lock.yaml"
run_pnpm "cold-resolve"
PNPM_COLD_RC="$(cat "$WORK/logs/pnpm-cold-resolve.rc")"
PNPM_COLD_REJECTED=0
if grep -q 'ERR_PNPM_NO_MATURE_MATCHING_VERSION\|ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION' \
    "$WORK/logs/pnpm-cold-resolve.out" || [[ "$PNPM_COLD_RC" -ne 0 ]]
then
    PNPM_COLD_REJECTED=1
fi

rm -rf "$WORK/project/node_modules" \
    "$WORK/project/pnpm-lock.yaml" \
    "$WORK/project/aube-lock.yaml"
run_aube "cold-resolve"
AUBE_COLD_RC="$(cat "$WORK/logs/aube-cold-resolve.rc")"
AUBE_COLD_INSTALLED=0
if [[ "$AUBE_COLD_RC" -eq 0 ]] && fresh_pkg_linked; then
    AUBE_COLD_INSTALLED=1
fi

echo
echo "scenario B matrix: pnpm_rejected=${PNPM_COLD_REJECTED} aube_installed=${AUBE_COLD_INSTALLED}"

########################################################################
# Scenario C: aube with minimumReleaseAgeStrict: true (control)
# Should reject like pnpm. Proves the setting is wired; default is not strict.
########################################################################

echo
echo "=== scenario C: aube minimumReleaseAgeStrict control ==="
cat >"$WORK/project/pnpm-workspace.yaml" <<'EOF'
minimumReleaseAge: 1440
minimumReleaseAgeStrict: true
EOF
rm -rf "$WORK/project/node_modules" \
    "$WORK/project/pnpm-lock.yaml" \
    "$WORK/project/aube-lock.yaml"
run_aube "strict"
AUBE_STRICT_RC="$(cat "$WORK/logs/aube-strict.rc")"
AUBE_STRICT_REJECTED=0
if grep -q 'ERR_AUBE_NO_MATURE_MATCHING_VERSION\|minimumReleaseAgeStrict' \
    "$WORK/logs/aube-strict.out" || [[ "$AUBE_STRICT_RC" -ne 0 ]]
then
    AUBE_STRICT_REJECTED=1
fi
echo "scenario C matrix: aube_strict_rejected=${AUBE_STRICT_REJECTED}"

echo
echo "versions:"
echo "  aube: ${AUBE_VERSION}"
echo "  real pnpm: ${PNPM_VERSION}"
if [[ -n "$AUBESHIM_VERSION" ]]; then
    echo "  aubeshim: ${AUBESHIM_VERSION}"
fi

# Gap is present when pnpm rejects young pins and aube accepts them under the
# default (non-strict) minimumReleaseAge settings that match pnpm 11's 1440.
GAP=0
if [[ "$PNPM_LOCK_REJECTED" -eq 1 && "$AUBE_LOCK_INSTALLED" -eq 1 ]]; then
    GAP=1
fi
if [[ "$PNPM_COLD_REJECTED" -eq 1 && "$AUBE_COLD_INSTALLED" -eq 1 ]]; then
    GAP=1
fi

if [[ "$GAP" -eq 1 ]]; then
    echo
    echo "observed: native pnpm enforces minimumReleaseAge on young pins / lockfile"
    echo "entries; aube installs them under the default non-strict age gate (and does"
    echo "not re-verify published age for existing lockfile entries)."
    if [[ "$AUBE_STRICT_REJECTED" -eq 1 ]]; then
        echo "note: aube does reject when minimumReleaseAgeStrict: true is set."
    fi
    exit 1
fi

if [[ "$PNPM_LOCK_REJECTED" -eq 0 && "$PNPM_COLD_REJECTED" -eq 0 ]]; then
    echo
    echo "setup anomaly: native pnpm did not reject the young package; mock registry" >&2
    echo "timestamps may not be reaching the age gate." >&2
    exit 2
fi

echo
echo "pass: aube rejected young packages in parity with native pnpm"
exit 0
