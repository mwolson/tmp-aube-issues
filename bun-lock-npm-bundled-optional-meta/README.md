# bun.lock gets aube's internal npm bundle metadata

`registry.cjs` serves a tiny npm registry on a free localhost port: `bundler@1.0.0`
bundles `inner` and the optional `opt` (`bundleDependencies: ["inner", "opt"]`),
and `inner` and `opt` are also published on their own, since Bun resolves
bundled names from the registry. The case resolves a project depending on
`bundler` into a `bun.lock`, once with real Bun and once with aube (seeded with
an empty `bun.lock` so aube picks the format), and prints the metadata slot of
the `bundler` entry.

aube writes `{ "__aube_npm_bundled_optional": { "opt": "1.0.0" } }`, an
internal key from its npm lockfile support, into that slot. Bun writes no such
key and drops it on its next `bun install`. The case fails when any `__aube`
key appears.

The `bun install` rewrite it prints also changes the URL column (`""` to the
tarball URL) because the registry is not npmjs.org; that part is unrelated.

```sh
AUBE_BIN=/path/to/aube BUN_BIN=/path/to/bun ./repro.sh
```

Requires Node and Bun (checked with Bun 1.4.3). `REPRO_WORK_DIR` moves the
generated projects and logs (default `.repro-work/`). Exit 2 means an
environment or control failure.

Observed 2026-10-25 with `aube 2.8.3 linux-x64 (2026-10-25)` on upstream main
`3c226195`: exit 1. Released 2.8.3, which predates the npm bundle metadata,
does not write the key.
