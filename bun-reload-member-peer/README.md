# Bun frozen reload changes a workspace consumer's peer provider

Three tiny local tarballs provide `react@18.0.0`, `react@19.0.0`, and `consumer`.
The React fixtures export their version strings. The root provides React 18;
workspace member `apps/app` provides React 19 and consumer, which declares
`react@^19.0.0` as a peer and exports `require("react")`.

Aube 2.8.2 and 2.8.2+mwolson.1 start from an empty `bun.lock`, write the lockfile,
and load 19.0.0 from the member's consumer. After deleting all project
`node_modules`, `--frozen-lockfile` exits 0 and preserves the lockfile bytes, but
the same runtime check loads root React 18.0.0.

Native Bun 1.4.3 generates its own lockfile from the same manifests and tarballs.
Its fresh and clean frozen installs both load 19.0.0; its frozen lockfile also
stays byte-identical. The native commands are:

```sh
bun install --ignore-scripts
```

```sh
bun install --frozen-lockfile --ignore-scripts
```

Run from this directory, using a real Bun binary:

```sh
AUBE_BIN=/path/to/aube BUN_BIN=/path/to/real/bun ./repro.sh
```

Requires Node.js, Python 3, Bun, and aube. No registry packages are needed. Exit
0 means the member keeps its React 19 peer, 1 means the reported bug occurs,
and 2 means setup or the native control failed. Every cache, store, fixture and
log stays under ignored `.repro-work/`.
