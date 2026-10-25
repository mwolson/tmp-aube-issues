# npm workspace local dependency specs fail frozen reload

A workspace member depends on `file:../../vendor/host`; host depends on a tiny
local `leaf` package. The script checks both directory and tarball leaf sources.
It creates a valid empty npm lockfile before adding the fixture dependencies,
then lets aube resolve and rewrite it.

Aube 2.8.2 and 2.8.2+mwolson.1 install and load `leaf` successfully, but record
`leaf: file+<hash>` in `packages["vendor/host"].dependencies` instead of the
manifest's `file:<absolute path>`. After deleting all project `node_modules`,
`--frozen-lockfile` rejects that unchanged manifest with
`vendor/host: manifest adds leaf@file:<path>`. The frozen attempt leaves the
lockfile unchanged.

Native npm 11.6.2 writes the declared spec, and both its fresh install and clean
`npm ci` load `leaf`. The native commands are:

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
