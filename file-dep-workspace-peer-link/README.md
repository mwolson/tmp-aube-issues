# A `file:` dependency cannot resolve its workspace peer

Observed with aube 2.6.1 on Linux x64. Native pnpm 12.8.1 installs the same
workspace correctly.

`apps/app` depends on a workspace package, `@x/shared` (`workspace:*`), and on
a local directory package, `@x/md` (`file:./modules/md`). `@x/md` declares
`@x/shared` as a peer dependency and requires it.

Pnpm records the resolved peer as `'@x/shared': link:packages/shared` under the
`@x/md` snapshot and links it to the workspace package, so
`require('@x/md')` works.

Aube fails both ways it can install this workspace:

- From the pnpm-written lockfile, `--frozen-lockfile` writes
  `node_modules/.aube/@x+md@file+<hash>/node_modules/@x/shared` as a symlink
  to `../../../@x+shared@link+packages+shared/node_modules/@x/shared`. Aube
  never creates that virtual-store entry, so the link dangles.
- From a fresh install with aube's own lockfile, the `@x/md` copy gets no
  `@x/shared` link at all.

Either way `require('@x/md')` fails with `MODULE_NOT_FOUND`. The hoisted
linker (`AUBE_NODE_LINKER=hoisted`) fails too.

## Run

Requires Bash, Python 3, Node.js, aube, and real pnpm. When using aubeshim, set
`PNPM_BIN` to a real pnpm executable, not the dispatcher:

```bash
PNPM_BIN=/absolute/path/to/real/pnpm ./repro.sh
```

The fixture is a three-package workspace with no registry dependencies. Each
install gets its own HOME and XDG directories. Pnpm runs first as the control
and its lockfile seeds the frozen aube case. Evidence stays under the ignored
`tmp/file-dep-peer.*` directory.

- Exit 0: aube links the peer in both cases.
- Exit 1: aube leaves the peer link dangling or missing.
- Exit 2: a required tool, the pnpm control, or another setup step failed.

## Results

| Install | pnpm 12.8.1 | aube 2.6.1 |
| --- | --- | --- |
| Fresh install | Pass | Fails: no peer link |
| Frozen install from pnpm's lockfile | Pass (writes it) | Fails: dangling peer link |

Found with `@t3tools/mobile-markdown-text` in pingdotgg/t3code, a
`file:./modules/t3-markdown-text` package in the Expo app that peers on the
workspace packages `@t3tools/shared` and `@t3tools/client-runtime`. The mobile
typecheck cannot resolve its workspace imports under aube.

Upstream discussion:
[#1677 file-dep-workspace-peer](https://github.com/aubepkg/aube/discussions/1677)
