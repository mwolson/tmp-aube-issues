# New npm lock entries follow the project's libc convention

npm 11.10.1 and older omit `libc` from `package-lock.json` entries; npm 11.11.0
and later write it (checked with `rollup@4.53.3`). An older npm strips the
field again on its next rewrite, so a lockfile flips back and forth whenever
the writer's convention differs from the project's npm.

This case adds `@rollup/rollup-linux-x64-gnu@4.53.3` to two projects, one whose
lockfile npm 11.6.2 wrote and one whose lockfile npm 11.20.0 wrote, and
compares aube's new entry with the matching real npm add. Both resulting
lockfiles must also pass a real `npm ci`. It requires Linux x64 with glibc.

Each fixture has one optional dependency, `@rollup/rollup-linux-x64-musl@4.53.3`,
so the npm 11.20.0 lockfile already carries a `libc` field without an unrelated
dependency tree. Each manifest pins its writer in `packageManager`. The
fixtures were generated with Node 22.22.0 and real npm 11.6.2 and 11.20.0,
with no lockfile edits:

```sh
npm install --package-lock-only --ignore-scripts --no-audit --no-fund
```

Run with real binaries and Node 22.22.0 first on PATH:

```sh
AUBE_BIN=/path/to/aube NPM_OLD_BIN=/path/to/npm-11.6.2 NPM_NEW_BIN=/path/to/npm-11.20.0 ./repro.sh
```

Set `REPRO_WORK_DIR` to put generated projects and logs elsewhere; the default
is `.repro-work/`. Caches and stores stay inside the run directory. Exit 2
means an environment or control failure.

Observed 2026-10-25 with `aube 2.8.3 linux-x64 (2026-10-25)` and upstream main
`79272433`: exit 1. aube writes `"libc": ["glibc"]` on the new entry in both
projects; npm 11.6.2 writes none for the first. Both controls and every
`npm ci` run pass.
