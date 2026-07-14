# aube issue repros

Minimal repros for aube compatibility issues found while testing
existing npm and Bun projects.

## Open

- [`pnpm-patch-reresolve-drop`](pnpm-patch-reresolve-drop) (observed with
  aube `1.26.0`, still present on master `730bc4ce` after the #1022 fix): a
  non-frozen `aube install` that re-resolves because of unrelated manifest
  drift (a new `is-positive` dependency the lockfile does not have yet) loses
  the pnpm-compatible patch metadata for a patch the workspace still declares
  and the lockfile still records correctly. On `1.26.0` the rewritten
  `pnpm-lock.yaml` keeps only an empty `patchedDependencies:` key and no
  `(patch_hash=...)` suffixes. On master, #1022 restores the top-level entry,
  but writes it in path form (`patches/is-odd@3.0.1.patch`) instead of the
  pnpm 11 hash form and still omits the `(patch_hash=...)` suffixes from
  importer and snapshot keys, so a subsequent native pnpm `11.11.0`
  `--frozen-lockfile` install fails with
  `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`. Native pnpm `11.11.0` re-resolves the
  same drifted state keeping both the applied patch and the full metadata.
  Both aube versions also link the patched package from a store directory
  without a patch label (`.aube/is-odd@3.0.1`); in a larger project where a
  plain-named store entry already existed unpatched, aube silently linked the
  unpatched content. Distinct from `pnpm-patch-stale-lock-path` /
  discussion #1019: there the lockfile records a patch the workspace no
  longer declares and aube fails hard; here the declaration and lockfile
  agree, the drift is unrelated, and the loss is silent.
  The fixture lockfile was produced by native pnpm `11.11.0` with the patch
  declared, then `is-positive` was added to `package.json` without rerunning
  install, as happens when a merge updates manifests but keeps the old lock.
  Docs: https://aube.jdx.dev/package-manager/lockfiles,
  https://aube.jdx.dev/pnpm-users
- [`pnpm-patch-stale-lock-path`](pnpm-patch-stale-lock-path) (observed with
  aube `1.26.0`, also reproduced on `1.25.2`): a non-frozen `aube install`
  fails with `failed to read patch file patches/is-odd@3.0.0.patch for
  is-odd@3.0.0: No such file or directory` when the committed `pnpm-lock.yaml`
  still records a `patchedDependencies` entry for a patch key and file that
  the workspace no longer declares. Native pnpm `10.24.0` and `11.11.0`
  re-resolve to the new version and apply the new patch from the same state.
  The stale lock and both patch files were produced by pnpm `10.24.0` using
  `pnpm install --ignore-scripts`, `pnpm patch is-odd@<version>`, and
  `pnpm patch-commit --patches-dir patches` while the manifest pinned
  `is-odd@3.0.0`; the manifest and workspace patch were then upgraded to
  `is-odd@3.0.1` (old patch file deleted) without rerunning install, as
  happens when a merge or rebase updates manifests but keeps the old lock.
  The repro passes `--no-frozen-lockfile` to both package managers so the
  comparison stays non-frozen even where `CI` is set.
  Aube succeeds when the old patch file still exists on disk, so the failing
  eager read is of a patch the new resolution never uses. With a pnpm `11`
  hash-only lockfile in the same drifted state, aube fails the same way but
  treats the hash string itself as the patch file path.
  Docs: https://aube.jdx.dev/package-manager/lockfiles,
  https://aube.jdx.dev/pnpm-users
  Upstream discussion: https://github.com/jdx/aube/discussions/1019
- [`pnpm-patch-plain-unified-diff`](pnpm-patch-plain-unified-diff) (observed
  with aube `1.26.0`, also reproduced on `1.25.2`): aube's patch applier only
  recognizes file sections introduced by a `diff --git` header line. A patch
  file written as a plain unified diff (starting directly with `--- a/...` /
  `+++ b/...`) fails `aube install` with `failed to apply patch for
  is-number@7.0.0: patch section missing file path`. Native pnpm `10.24.0`
  and `11.11.0` apply the same patch file from the same
  `pnpm-workspace.yaml` `patchedDependencies` entry. Found while migrating a
  pnpm workspace whose patches included one hand-written unified diff;
  prepending a `diff --git a/<path> b/<path>` header line makes aube accept
  the patch, which is the current workaround.
  Docs: https://aube.jdx.dev/cli/patch-commit,
  https://aube.jdx.dev/pnpm-users
  Upstream discussion: https://github.com/jdx/aube/discussions/1018

## Fixed

- [`pnpm-bin-workspace-flag`](pnpm-bin-workspace-flag) (observed with aube
  `1.23.0`, fixed in aube `1.26.0`): pnpm's `bin -w` prints the workspace-root
  `node_modules/.bin` from a workspace package. Aube already supported the
  long `--workspace-root` global flag, and now accepts `-w`,
  `--workspace-root`, and `--workspace` directly on `aube bin`. The repro
  confirms `aube bin -w` matches native pnpm's output from a workspace package.
  Docs: https://aube.jdx.dev/cli/bin.html,
  https://aube.jdx.dev/pnpm-users.html
  Upstream discussion: https://github.com/jdx/aube/discussions/988
  Upstream fix: https://github.com/jdx/aube/pull/993
- [`global-outdated-packages`](global-outdated-packages) (observed with aube
  `1.21.0`, fixed in aube `1.23.0`): aube supports global package installs and
  global updates, but `aube outdated -g` was rejected with an unexpected
  argument error instead of checking globally installed packages. The repro
  installs `is-positive@1.0.0` into an isolated aube global directory, confirms
  the package is globally listed, and then shows `aube outdated -g` reports the
  stale global version. aube returns exit code `1` when outdated globals exist,
  matching npm-style outdated semantics.
  Docs: https://aube.jdx.dev/package-manager/dependencies.html,
  https://aube.jdx.dev/cli/outdated
  Upstream fix: https://github.com/jdx/aube/pull/910
- [`dlx-allow-build-flag`](dlx-allow-build-flag) (observed with aube `1.18.0`,
  fixed in aube `1.18.2`): `aube dlx --allow-build=esbuild vite --version`
  treated `--allow-build=esbuild` as the package to execute and failed with an
  invalid package-name registry error. pnpm `11.3.0` accepts the same `dlx`
  flag, and pnpm documents `pnx`, `pnpm dlx`, and `pnpx` as aliases that
  support `--allow-build` for allowing named packages to run postinstall scripts
  during the temporary install.
  Docs: https://pnpm.io/cli/pnx,
  https://aube.jdx.dev/package-manager/lifecycle-scripts,
  https://aube.jdx.dev/cli/add
- [`bun-patched-dependencies`](bun-patched-dependencies) (observed with aube
  `1.14.1`, fixed in aube `1.15.0`): aube installs from Bun's text `bun.lock`,
  but it does not apply Bun's top-level `patchedDependencies` manifest field.
  Native Bun applies the patch from the same manifest and lockfile. Aube
  documents patch support through `aube.patchedDependencies` /
  `pnpm.patchedDependencies`, but the Bun rollout docs do not mention Bun's
  top-level field.
  Docs: https://aube.jdx.dev/package-manager/configuration,
  https://aube.jdx.dev/bun-users
  Upstream discussion: https://github.com/jdx/aube/discussions/722
- [`bun-workspace-link`](bun-workspace-link) (observed with aube `1.13.1`,
  fixed in aube `1.14.1`): aube installs from Bun's text `bun.lock`, but a
  workspace dependency symlink inside `packages/app` points to the workspace
  root instead of `packages/contracts`.
  Upstream discussion: https://github.com/jdx/aube/discussions/691
- [`npm-lock-missing-entry`](npm-lock-missing-entry) (observed with aube
  `1.14.0`, fixed in aube `1.14.1`): aube repairs a stale npm
  `package-lock.json` by adding the root `expo-router` dependency spec,
  but it does not add `packages["node_modules/expo-router"]`. A clean frozen
  aube install then omits `node_modules/expo-router`. The stale npm lock was
  produced by npm `11.14.1` from the same manifest before `expo-router` was
  added, using `npm install --package-lock-only --ignore-scripts --no-audit
  --no-fund`.
  Upstream discussion: https://github.com/jdx/aube/discussions/690
- [`yarn-hoisted-transitive-dependency`](yarn-hoisted-transitive-dependency)
  (observed with aube `1.14.1`, fixed in aube `1.15.0`): aube hoisted mode
  installs from a Yarn v1 `yarn.lock`, but the materialized dependency tree
  does not make `magic-string`'s declared dependency `sourcemap-codec`
  resolvable from `magic-string`. Native Yarn v1.22.22 installs the same
  lockfile with that dependency resolvable. This was first seen through a
  `react-scripts@5.0.0` hoisted-mode failure on `react-dev-utils/crossSpawn`,
  but reduces to this smaller transitive dependency case. The repro disables
  aube's global virtual store so unrelated cached installs cannot mask the
  missing dependency.
  Docs: https://aube.jdx.dev/package-manager/node-modules,
  https://aube.jdx.dev/package-manager/lockfiles,
  https://aube.jdx.dev/troubleshooting
  Upstream discussion: https://github.com/jdx/aube/discussions/725
- [`yarn-scoped-dependency-linking`](yarn-scoped-dependency-linking) (observed
  with aube `1.14.1`, fixed in aube `1.15.0`): aube installs from a Yarn v1
  `yarn.lock`, but the materialized dependency tree does not make
  `@rollup/plugin-replace`'s declared dependency `@rollup/pluginutils`
  resolvable from `@rollup/plugin-replace`. Native Yarn v1.22.22 installs the
  same lockfile with that dependency resolvable. This was first seen through a
  `react-scripts@5.0.0` build failure involving `workbox-build`, but reduces
  to this smaller scoped-dependency case. The repro disables aube's global
  virtual store so unrelated cached installs cannot mask the missing scoped
  dependency.
  Docs: https://aube.jdx.dev/package-manager/node-modules,
  https://aube.jdx.dev/package-manager/lockfiles,
  https://aube.jdx.dev/troubleshooting
  Upstream discussion: https://github.com/jdx/aube/discussions/723

## Mitigated

- [`package-config-symlink-resolution`](package-config-symlink-resolution)
  (observed with aube `1.15.0`, still present with aube `1.17.1` in default
  isolated mode): aube installs a package whose config file requires one of that
  package's declared dependencies, but loading that config through the package's
  top-level `node_modules/<pkg>` symlink cannot resolve the declared dependency.
  Loading the same file through `fs.realpathSync` succeeds because Node's
  resolver then starts inside the aube virtual-store package directory. This was
  first seen through Expo / React Native autolinking, where `expo`'s
  `react-native.config.js` requires `expo-modules-autolinking/exports`; if that
  config load fails, autolinking falls back to parsing native sources and
  generates an invalid `expo.core.ExpoModulesPackage` import. The reduced repro
  also fails with pnpm `11.1.3`, so this is an isolated symlink layout
  compatibility edge rather than an aube-only divergence from pnpm.
  Mitigated by `aube install --node-linker=hoisted`, and by aubeshim `0.6.0`
  for npm-shaped local commands, which runs npm-shimmed aube invocations with
  `AUBE_NODE_LINKER=hoisted` unless the caller already selected a node linker.
  Upstream discussion: https://github.com/jdx/aube/discussions/754
- [`install-omit-optional`](install-omit-optional) (observed with aube
  `1.14.1`, still present in aube `1.15.0`): aube rejects
  `aube install --omit optional` with an unexpected argument error. This blocks
  npm/Bun-compatible production install commands that use `--omit optional`;
  aube's documented equivalent is `--no-optional`. Mitigated in aubeshim
  `0.5.0`, which translates npm/Bun `--omit optional` to aube `--no-optional`
  and npm/Bun `--omit dev` to aube `--prod`.
  Docs: https://aube.jdx.dev/package-manager/install

Each case has a `repro.sh` script that exits zero when aube behaves correctly
and non-zero when the issue is observed.
