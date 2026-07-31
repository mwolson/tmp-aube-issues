#!/bin/bash
set -euo pipefail

# pnpm-workspace.yaml and patches/ are mutated by `aube patch-commit`, so the
# committed pristine copies live under pristine/ and are materialized per run.

for cmd in aube grep node; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        exit 2
    fi
done

cd "$(dirname "$0")"

ORIGINAL_MARKER='aube-repro original patch marker'
SECOND_MARKER='aube-repro second patch marker'
INSTALLED=node_modules/@isaacs/string-locale-compare/index.js

rm -rf node_modules aube-lock.yaml patches pnpm-workspace.yaml
cp pristine/pnpm-workspace.yaml .
cp -r pristine/patches .

if ! aube install --ignore-scripts --reporter append-only; then
    echo "aube install failed on the pristine existing patch; fix the environment and retry" >&2
    exit 2
fi
if ! grep -q "$ORIGINAL_MARKER" "$INSTALLED"; then
    echo "baseline install did not apply the existing patch; fix the environment and retry" >&2
    exit 2
fi

edit_output="$(aube patch @isaacs/string-locale-compare@1.1.0)"
edit_dir="$(printf '%s\n' "$edit_output" | sed -n 's/^You can now edit the following folder: //p')"
if [[ -z "$edit_dir" || ! -d "$edit_dir" ]]; then
    echo "could not parse the edit folder from aube patch output:" >&2
    printf '%s\n' "$edit_output" >&2
    exit 2
fi
if ! grep -q "$ORIGINAL_MARKER" "$edit_dir/index.js"; then
    echo "aube patch did not apply the existing patch to the edit folder" >&2
    exit 2
fi

printf '\n// %s\n' "$SECOND_MARKER" >> "$edit_dir/index.js"

status=0
if ! aube patch-commit "$edit_dir"; then
    echo "issue: aube patch-commit failed to relink after editing an already-patched package" >&2
    status=1
fi

declared_patch="$(sed -n 's/^  "@isaacs\/string-locale-compare@1.1.0": //p' pnpm-workspace.yaml)"
if [[ -z "$declared_patch" || ! -f "$declared_patch" ]]; then
    echo "issue: pnpm-workspace.yaml no longer declares an existing patch file (declared: ${declared_patch:-none})" >&2
    status=1
else
    for marker in "$ORIGINAL_MARKER" "$SECOND_MARKER"; do
        if ! grep -q "^+.*$marker" "$declared_patch"; then
            echo "issue: declared patch file $declared_patch does not add: $marker" >&2
            status=1
        fi
    done
fi

rm -rf node_modules aube-lock.yaml
if ! aube install --ignore-scripts --reporter append-only; then
    echo "issue: aube install failed after patch-commit" >&2
    status=1
elif [[ -f "$INSTALLED" ]]; then
    for marker in "$ORIGINAL_MARKER" "$SECOND_MARKER"; do
        if ! grep -q "$marker" "$INSTALLED"; then
            echo "issue: installed package is missing: $marker" >&2
            status=1
        fi
    done
else
    echo "issue: installed package file is missing after patch-commit" >&2
    status=1
fi

if [[ "$status" -eq 0 ]]; then
    echo "pass: patch-commit combined the new edit with the existing patch"
fi
exit "$status"
