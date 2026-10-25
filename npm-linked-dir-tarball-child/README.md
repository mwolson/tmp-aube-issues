# npm frozen reload loses a linked directory's tarball child

The root depends on `host` through `file:vendor/host`; host declares and requires
`leaf` from a tiny local tarball. There are no workspaces. The script creates a
valid empty npm lockfile before adding the fixture dependencies, then lets aube
resolve and rewrite it.

Aube 2.8.2 and 2.8.2+mwolson.1 install and load `leaf` successfully. After deleting
all project `node_modules`, `--frozen-lockfile` exits 0 with an unchanged
`package-lock.json`, but requiring host follows the live `vendor/host` directory
and fails with `MODULE_NOT_FOUND: Cannot find module 'leaf'`.

Native npm 11.6.2 installs the same fixture and loads `leaf` after both its fresh
install and clean `npm ci`. The native commands are:

```sh
npm install --package-lock-only --ignore-scripts --no-audit --no-fund
```

```sh
npm install --ignore-scripts --no-audit --no-fund
```

```sh
npm ci --ignore-scripts --no-audit --no-fund
```

Run from this directory, using a real npm binary:

```sh
AUBE_BIN=/path/to/aube NPM_BIN=/path/to/real/npm ./repro.sh
```

Requires Node.js, Python 3, npm, and aube. Packages are generated locally; no
registry packages are needed. Exit 0 means the lifecycle works, 1 means the
reported bug occurs, and 2 means setup or the native control failed. Every
cache, store, fixture and log stays under ignored `.repro-work/`.
