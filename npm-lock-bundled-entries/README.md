# Existing npm bundle entries lose their bundle declaration

An unrelated `aube add is-number@7.0.0` drops `bundleDependencies` from an
existing npm lock entry. npm ci then treats its bundled dependency as an
ordinary dependency and fails with `Missing: tslib@2.8.1 from lock file`.

The bundle fixture needs only two root dependencies: optional
`@tailwindcss/oxide-wasm32-wasi@4.1.14`, which bundles tslib, and `tslib@2.3.0`,
which cannot satisfy the bundle's `^2.4.0` declaration. Removing the root tslib
still shows metadata loss but no npm ci failure. On Linux x64, real npm 11.6.2
generated the three-entry lockfile with this command:

```sh
npm install --ignore-scripts --no-audit --no-fund
```

The optional wasm package is platform filtered, so npm writes its bundle
metadata without enumerating children. This is npm-generated input, with no
manual lockfile pruning. The script verifies the complete bundle list and
its dependency declarations after both npm's and aube's unrelated add, then
runs clean npm ci on each result.

A second fixture isolates nested placement loss with just `whatwg-url@5.0.0`
and dev `data-urls@7.0.0`. The latter needs a newer whatwg-url, whose tr46 and
webidl-conversions dependencies are placed beside it under data-urls. aube
removes those two valid paths. Its replacement layout still passes npm ci;
the regression here concerns preserving existing placements. That fixture
was generated with npm 10.8.2:

```sh
npm install --package-lock-only --ignore-scripts --no-audit --no-fund
```

Run with real binaries, avoiding package-manager shims:

```sh
AUBE_BIN=/path/to/aube NPM_BIN=/path/to/real/npm ./repro.sh
```

Tested on Linux x64 with npm 11.6.2: aube `2.8.2 linux-x64 (2026-10-23)`
exits 1; `2.8.2+mwolson.1 linux-x64 (2026-10-24)` exits 0. The fork preserves
the bundle metadata and nested paths, and npm ci succeeds for both fixtures.
The native npm controls preserve the checked entries and pass npm ci in both
runs. All caches and stores stay in `.repro-work/`. Exit 2 means an environment
or control failure.
