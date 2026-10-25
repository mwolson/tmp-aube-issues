# Absolute local child of a tarball dependency

`host.tgz` depends on `child.tgz` through an absolute `file:` specifier.
Released aube 2.8.2 rejects the child even with `block-exotic-subdeps=false`.
pnpm 12.14.0, npm 11.6.2, and Bun 1.4.3 accept the absolute tarball child.

Run with real aube and pnpm binaries on PATH, or set `AUBE_BIN` and `PNPM_BIN`:

```sh
./repro.sh
```

The script generates both tarballs under `.repro-work/`, putting the current
absolute child path into the host manifest. It checks pnpm fresh and clean
frozen installs, then the equivalent aube lifecycle and unchanged lockfile.
All stores and caches stay under `.repro-work/`. No registry packages are needed.

Exit 0 means both tools passed; exit 1 means aube failed; exit 2 means a
prerequisite or the pnpm control failed. Relative child paths are deliberately
excluded because pnpm and npm assign them different anchors for tarball parents.
