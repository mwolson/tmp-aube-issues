# Removed dependency leaves a stale bin shim

Observed with `aube 2.6.0 linux-x64 (2026-09-28)` and Node `v26.8.1`.

```sh
./repro.sh
```

The script exits zero when removed dependency bins disappear and scripts use
the replacement executable on PATH. It exits one when a stale bin survives,
or two if an install, explicit fixture check, or clean-install control fails.
Other setup errors abort immediately. Set `AUBE_BIN` to
test another executable. Each run creates fresh projects and keeps logs in
this case's ignored `tmp/` directory.

The fixture contains only `semver@7.7.2`, a pure-JavaScript package with no
dependencies. It provides the removed command. Before cache expiry, the
removed package entry and its bin both survive, so the command still runs;
aging the entry reproduces the dangling-shim failure with this single package.

Aube intentionally retains orphaned virtual-store entries for seven days
under the default
[`modulesCacheMaxAge`](https://aube.en.dev/settings/#setting-modulescachemaxage).
The script sets the local semver entry's mtime to eight days ago using
`fs.lutimesSync`. This simulates elapsed cache age without deleting package
files or changing the shared store. The retention setting is pinned to its
default `10080` minutes for reproducibility. Isolated linking and the requested
global virtual store mode are set explicitly. `preferSymlinkedExecutables`
is set to `false`, the isolated layout's default. The script verifies the bin
is a regular-file wrapper and checks whether the local package-store entry is
a symlink or a directory before removing the dependency.

The matrix tests the global virtual store enabled and disabled with each path:

1. `aube remove semver`.
2. Delete semver from `package.json`, then `aube install`.
3. Generate updated manifest and lockfile in a separate directory with
   `aube install --lockfile-only`, copy them over the existing project's
   manifest and lockfile, then `aube install`. This simulates pulling a
   committed removal while retaining the old `node_modules` tree.

All six cases reproduce on 2.6.0. Semver disappears from the manifest,
lockfile, and local virtual store, but `node_modules/.bin/semver` survives.
A follow-up plain `aube install` reports `Already up to date` and leaves it.
`aube run check` puts `.bin` ahead of PATH and exits one with
`MODULE_NOT_FOUND` for `.aube/semver@7.7.2/node_modules/semver/bin/semver.js`,
instead of running the fixture's PATH executable and printing `PATH-fallback`.

`aube install --force` and `aube prune` also leave the shim in this minimal
fixture. `aube ci` performs a clean install, removes it, and restores the PATH
fallback. The script checks that control before returning its failure result.
