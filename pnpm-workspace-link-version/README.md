# Aube writes workspace packages into pnpm-lock.yaml by version

Observed with aube 2.7.0 on Linux x64, also 2.6.1 and 1.41.0. Native pnpm
11.10.0 and 12.8.1 reject the result.

`packages/app` depends on two workspace packages, `@x/shared` (version 1.2.3)
and `@x/extra`, through `workspace:*`, and on a local directory package,
`@x/md` (`file:../../modules/md`), which peers on `@x/shared`. The committed
`pnpm-lock.yaml` was written by pnpm 11.10.0 before `@x/extra` was added.

pnpm records workspace packages as `link:` paths:

```yaml
importers:
  packages/app:
    dependencies:
      '@x/md':
        specifier: file:../../modules/md
        version: file:modules/md(@x/shared@packages+shared)
      '@x/shared':
        specifier: workspace:*
        version: link:../shared

snapshots:
  '@x/md@file:modules/md(@x/shared@packages+shared)':
    dependencies:
      '@x/shared': link:packages/shared
```

After `aube install --no-frozen-lockfile` on the drifted manifest, every
workspace reference carries the package's own version instead, and the `file:`
package loses its peer suffix:

```yaml
      '@x/extra':
        specifier: workspace:*
        version: 1.0.0
      '@x/md':
        specifier: file:../../modules/md
        version: file:modules/md
      '@x/shared':
        specifier: workspace:*
        version: 1.2.3

snapshots:
  '@x/md@file:modules/md':
    dependencies:
      '@x/shared': 1.2.3
```

Aube installs from that lockfile, but pnpm's frozen install fails:

```text
[ERR_PNPM_LOCKFILE_MISSING_DEPENDENCY] Broken lockfile: no entry for '@x/extra@1.0.0' in pnpm-lock.yaml
```

Recovery depends on the pnpm version. A non-frozen pnpm 11.10.0 install
restores the `link:` versions. Pnpm 12.8.1 fails the same way without
`--frozen-lockfile` and with `--fix-lockfile`, so the lockfile has to be
regenerated or fixed by hand. The same rewrite happens with no manifest drift
under `aube install --no-frozen-lockfile`.

Found in pingdotgg/t3code: adding one unrelated dependency and running aube
rewrote about 1,650 lockfile lines, and pnpm's frozen install failed with
`no entry for '@t3tools/client-runtime@0.0.0'`. Restoring only the 32 workspace
`link:` values (30 importer entries and two peers in a `file:` package's
snapshot) made that lockfile frozen-install under pnpm 11.10.0, so the
remaining churn there (peer-suffix spelling, dropped
`transitivePeerDependencies`) does not break pnpm.

## Run

Requires Bash, Node.js, aube, and real pnpm. The fixture has no registry
dependencies. When using aubeshim, set `PNPM_BIN` to a real pnpm executable,
not the dispatcher:

```bash
PNPM_BIN=/absolute/path/to/real/pnpm ./repro.sh
```

Pnpm runs first as the control on a copy under the ignored `.repro-work/`. Aube
then runs on a fresh copy, and pnpm frozen-installs aube's lockfile.

- Exit 0: aube keeps the `link:` versions and pnpm accepts its lockfile.
- Exit 1: aube writes workspace versions, or pnpm rejects its lockfile.
- Exit 2: missing tools or an invalid pnpm control.
