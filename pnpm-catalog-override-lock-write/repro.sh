#!/bin/bash
set -euo pipefail

# aube vs native pnpm: catalog: overrides written into pnpm-lock.yaml.
#
# pnpm 11 stores the catalog-resolved override value in two lockfile fields:
#   overrides: { is-number: 7.0.0 }
#   importers.*.specifier: 7.0.0
# even when pnpm-workspace.yaml says `overrides: { is-number: "catalog:" }`
# and package.json says `"is-number": "catalog:"`.
#
# aube 1.41.0 already *reads* that pnpm shape (discussion #174 / PR #249).
# When aube *writes* the lockfile (`add` or a non-frozen install after a
# manifest change) it stores the raw `catalog:` string in both fields.
# Official pnpm then rejects the lockfile in frozen CI:
#   ERR_PNPM_LOCKFILE_CONFIG_MISMATCH  (overrides: catalog:)
#   ERR_PNPM_OUTDATED_LOCKFILE         (specifier: catalog: vs manifest 7.0.0)
#
# First seen committing an `@opencode-ai/client` pin in pingdotgg/t3code
# (#5251) after `aube add` / `aube install` rewrote a green pnpm lockfile.
#
# Exit 0 = aube writes the pnpm-resolved shape. Exit 1 = gap observed.
# Exit 2 = missing tools / setup failure.

AUBE_BIN="${AUBE_BIN:-aube}"

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
        "${HOME}/.local/share/mise/installs/pnpm/11.22.0/pnpm"
    do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
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

echo "aube: $("$AUBE_BIN" --version 2>/dev/null | head -n 1 || true)"
echo "pnpm: $("$PNPM_BIN" --version 2>/dev/null | head -n 1 || true)"

setup() {
    rm -rf .repro-work
    mkdir -p .repro-work/packages/app
    cp package.json pnpm-workspace.yaml .repro-work/
    cp packages/app/package.json .repro-work/packages/app/
}

lockfile_override_is_resolved() {
    grep -qE "^  is-number: ['\"]?7\.0\.0['\"]?$" pnpm-lock.yaml
}

lockfile_override_is_catalog() {
    grep -qE "^  is-number: ['\"]catalog:['\"]$" pnpm-lock.yaml
}

importer_specifier_is_resolved() {
    python3 - <<'PY'
from pathlib import Path
lines = Path("pnpm-lock.yaml").read_text().splitlines()
in_app = False
for i, line in enumerate(lines):
    if line == "  packages/app:":
        in_app = True
        continue
    if in_app and line.startswith("  ") and not line.startswith("    ") and line.endswith(":"):
        break
    if in_app and line.strip() == "is-number:":
        if i + 1 < len(lines) and "specifier: 7.0.0" in lines[i + 1]:
            raise SystemExit(0)
        if i + 1 < len(lines) and "specifier: '7.0.0'" in lines[i + 1]:
            raise SystemExit(0)
raise SystemExit(1)
PY
}

setup
cd .repro-work
if ! CI=1 "$PNPM_BIN" install --ignore-scripts --lockfile-only; then
    echo "native pnpm could not write the starting lockfile" >&2
    exit 2
fi
if ! lockfile_override_is_resolved; then
    echo "native pnpm did not store the resolved override value 7.0.0" >&2
    exit 2
fi
if ! importer_specifier_is_resolved; then
    echo "native pnpm did not store importer specifier 7.0.0" >&2
    exit 2
fi
if ! CI=1 "$PNPM_BIN" install --frozen-lockfile --ignore-scripts; then
    echo "native pnpm rejected its own starting lockfile" >&2
    exit 2
fi
cd "$ROOT"

setup
cd .repro-work
CI=1 "$PNPM_BIN" install --ignore-scripts --lockfile-only
if ! "$AUBE_BIN" add --filter app is-odd@3.0.1 --ignore-scripts --reporter append-only; then
    echo "aube add failed" >&2
    exit 1
fi

fail=0
if lockfile_override_is_catalog; then
    echo "aube wrote lockfile overrides as catalog: instead of 7.0.0"
    fail=1
elif ! lockfile_override_is_resolved; then
    echo "aube wrote an unexpected overrides.is-number value"
    fail=1
fi
if ! importer_specifier_is_resolved; then
    echo "aube wrote importer specifier catalog: instead of 7.0.0"
    fail=1
fi

set +e
CI=1 "$PNPM_BIN" install --frozen-lockfile --ignore-scripts >/tmp/aube-catalog-override-pnpm-frozen.log 2>&1
pnpm_status=$?
set -e
if [[ "$pnpm_status" -eq 0 ]]; then
    echo "native pnpm accepted aube's rewritten lockfile"
else
    echo "native pnpm rejected aube's rewritten lockfile:"
    if grep -q "ERR_PNPM_LOCKFILE_CONFIG_MISMATCH" /tmp/aube-catalog-override-pnpm-frozen.log; then
        echo "  ERR_PNPM_LOCKFILE_CONFIG_MISMATCH (overrides)"
    fi
    if grep -q "ERR_PNPM_OUTDATED_LOCKFILE" /tmp/aube-catalog-override-pnpm-frozen.log; then
        echo "  ERR_PNPM_OUTDATED_LOCKFILE (importer specifier)"
    fi
    fail=1
fi

# Second layer: restoring only the overrides map still leaves the importer
# specifier as catalog:, which official pnpm reports as manifest 7.0.0.
if lockfile_override_is_catalog; then
    python3 - <<'PY'
from pathlib import Path
path = Path("pnpm-lock.yaml")
text = path.read_text()
old = "overrides:\n  is-number: 'catalog:'\n"
new = "overrides:\n  is-number: 7.0.0\n"
if old not in text:
    old = 'overrides:\n  is-number: "catalog:"\n'
if old not in text:
    raise SystemExit("could not locate aube catalog override block")
path.write_text(text.replace(old, new, 1))
PY
    set +e
    CI=1 "$PNPM_BIN" install --frozen-lockfile --ignore-scripts >/tmp/aube-catalog-override-pnpm-spec.log 2>&1
    spec_status=$?
    set -e
    if [[ "$spec_status" -eq 0 ]]; then
        echo "native pnpm accepted the lockfile after restoring resolved overrides"
    elif grep -q "is-number (lockfile: catalog:, manifest: 7.0.0)" /tmp/aube-catalog-override-pnpm-spec.log; then
        echo "after restoring overrides, native pnpm still rejects importer specifier catalog:"
        fail=1
    else
        echo "after restoring overrides, native pnpm failed unexpectedly:"
        tail -n 20 /tmp/aube-catalog-override-pnpm-spec.log
        fail=1
    fi
fi

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "pass: aube wrote catalog-resolved override and importer specifiers"
