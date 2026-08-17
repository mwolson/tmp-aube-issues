# aube issue repros

Minimal repros for aube compatibility issues found while testing
existing npm and Bun projects.

## Open

None.

## Intentional

Confirmed aube design differences from pnpm (or other managers). Kept for
migration notes; the repro still exits non-zero while the difference holds.

- [`pnpm-min-release-age`](pnpm-min-release-age) (observed with aube
  `1.37.0`, retested on `1.37.0`): aube documents pnpm 11's default
  `minimumReleaseAge: 1440` (24h), but under the default
  `minimumReleaseAgeStrict: false` it still installs an exact pin whose only
  matching version was published "now", and it does not re-verify published
  age for existing lockfile entries. Native pnpm 11 rejects the same tree
  with `ERR_PNPM_NO_MATURE_MATCHING_VERSION` on cold resolve and
  `ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION` when reinstalling from a lockfile
  that already pins the young version. Setting `minimumReleaseAgeStrict: true`
  makes aube reject on resolve (`ERR_AUBE_NO_MATURE_MATCHING_VERSION`).
  Maintainer confirmed this is intentional: lockfile pins are authoritative,
  and the age gate applies when resolving a new version rather than
  revalidating existing lock entries; strict mode is the opt-in hard fail on
  fresh resolve. The associated fix PR was closed without merge. The repro uses
  a local mock registry that always reports `publishedAt=now` so the case is
  durable without a same-day public publish. Migration note: projects that
  relied on pnpm 11's default hard age gate should set
  `minimumReleaseAgeStrict: true` (and not expect lockfile re-verification).
  First seen installing `@opencode-ai/sdk@0.0.0-beta-202608061351` in a
  monorepo that relied on the pnpm 11 default age gate (no explicit
  `minimumReleaseAge` key).
  Docs: https://aube.jdx.dev/security,
  https://aube.jdx.dev/settings/#setting-minimumreleaseage,
  https://pnpm.io/supply-chain-security
  Upstream discussion: https://github.com/jdx/aube/discussions/1240
  Closed PR (not merged): https://github.com/jdx/aube/pull/1241

## Fixed

- [`isolated-patched-gvs-stale-identity`](isolated-patched-gvs-stale-identity)
  (observed with aube `1.40.0`, fixed in aube `1.41.0`, retested on
  `1.41.0`): isolated installs with the default-on global virtual store used
  to leave a third-party package's sibling `node_modules/<dep>` pointing at a
  different store identity than the project importer. A warm `aube install`
  did not rewrite that nested GVS link, while
  `--disable-global-virtual-store` repaired it. Aube `1.41.0` now reconciles
  stale, missing, and incorrectly targeted nested links during warm installs
  and GVS cache hits. First seen
  when a patched `effect@4.0.0-beta.103` existed as both
  `effect@4.0.0-beta.103-<hash>` and
  `effect@4.0.0-beta.103_patch_hash=...` and Rolldown inlined both,
  splitting Effect's pre-response WeakMap. Native pnpm `11.21.0`
  isolated keeps one `is-number@7.0.0_patch_hash=...` identity for the
  app and `to-regex-range`. Distinct from
  [`hoisted-workspace-shared-dep-realpath`](hoisted-workspace-shared-dep-realpath)
  (hoisted, same version, fixed in `1.38.1`) and from
  [`metro-gvs-package-resolve`](metro-gvs-package-resolve) (Metro file
  map, not Node identity).
  Docs: https://aube.jdx.dev/package-manager/global-virtual-store,
  https://aube.jdx.dev/package-manager/node-modules
  Related:
  [#1242 hoisted-shared-realpath](https://github.com/jdx/aube/discussions/1242) /
  [#1243 workspace-hoisted-planner](https://github.com/jdx/aube/pull/1243)
  Upstream discussion: https://github.com/jdx/aube/discussions/1298
  Upstream fix: https://github.com/jdx/aube/pull/1299

- [`metro-gvs-package-resolve`](metro-gvs-package-resolve) (observed with aube
  `1.40.0`, fixed in aube `1.41.0`, retested on `1.41.0`): isolated installs
  with the default-on global virtual store
  make `node_modules/<pkg>` a symlink whose realpath is
  `$XDG_CACHE_HOME/aube/virtual-store/...`. Node resolves that package.
  Metro 0.84.4 does not: `Metro.buildGraph` reports
  `Unable to resolve module is-number` and, if `extraNodeModules` points
  at the realpath, lists that GVS path as an extra search directory and
  still fails. Adding the GVS package realpath to Metro `watchFolders`
  fixes it. `aube install --disable-global-virtual-store` and
  `node-linker=hoisted` keep the realpath inside the project and Metro
  succeeds. Native pnpm `11.21.0` isolated also succeeds because
  `.pnpm/` stays in the project; pnpm with
  `enableGlobalVirtualStore=true` fails the same way. First seen as
  Metro `Unable to resolve "expo/virtual/env"` in an Expo 56 app after
  Babel injected that import. aubeshim's hoisted linker injection is not
  required to reproduce this. Before aube `1.41.0`, `metro`, `expo`, and
  `react-native` were not on the default
  `disableGlobalVirtualStoreForPackages` list.
  Docs: https://aube.jdx.dev/package-manager/global-virtual-store,
  https://aube.jdx.dev/package-manager/node-modules,
  https://aube.jdx.dev/troubleshooting,
  https://metrobundler.dev/docs/configuration/#watchfolders
  Related: [#32 next-gvs-auto-disable](https://github.com/jdx/aube/pull/32) /
  [#101 gvs-auto-disable-list](https://github.com/jdx/aube/pull/101) added the
  GVS auto-disable list;
  [#117 trim-gvs-auto-disable-list](https://github.com/jdx/aube/pull/117)
  dropped names that lacked a concrete repro;
  [#754 config-symlink-resolution](https://github.com/jdx/aube/discussions/754)
  is isolated config-loader resolution, not Metro's file map.
  Aube `1.41.0` adds `metro`, `expo`, and `react-native` to the default
  `disableGlobalVirtualStoreForPackages` list. A default isolated install
  now warns, materializes packages inside the project, and passes the Metro
  graph build. Explicit `--enable-global-virtual-store` still overrides the
  compatibility detection and reproduces the upstream Metro limitation by
  design.
  Upstream discussion: https://github.com/jdx/aube/discussions/1294
  Upstream fix: https://github.com/jdx/aube/pull/1297

- [`hoisted-react-peer-duplication`](hoisted-react-peer-duplication)
  (observed with aube `1.40.0`, fixed in aube `1.41.0`, retested on
  `1.41.0`): in a two-importer workspace, the
  alphabetically earlier package pins `react@19.2.3` and the later one pins
  `react@19.2.6` plus `zustand@5.0.11` (`peer react: ">=18.0.0"`, optional).
  Isolated aube shares one `react@19.2.6` realpath between web and zustand.
  `aube install --node-linker=hoisted` used to let mobile claim the
  workspace-root `react` slot with `19.2.3`, then materialize `19.2.6` twice
  (`packages/web/node_modules/react` and
  `node_modules/zustand/node_modules/react`). Node loads two module
  identities of the same version. Native pnpm `11.21.0` and `10.24.0`
  hoisted place `19.2.6` once at the workspace root and nest only
  `19.2.3` under mobile. Aube `1.41.0` now ranks conflicting hoisted versions
  across the workspace and places the more widely used `19.2.6` at the root,
  so web and zustand share one React identity. Distinct from
  [`hoisted-workspace-shared-dep-realpath`](hoisted-workspace-shared-dep-realpath)
  (same version across importers, fixed in aube `1.38.1`) and from
  [`hoisted-workspace-auto-install-freshness`](hoisted-workspace-auto-install-freshness)
  (warm-path slot check).
  Docs: https://aube.jdx.dev/package-manager/node-modules,
  https://aube.jdx.dev/package-manager/workspaces
  Related:
  [#1242 hoisted-shared-realpath](https://github.com/jdx/aube/discussions/1242) /
  [#1243 workspace-hoisted-planner](https://github.com/jdx/aube/pull/1243)
  shared one physical
  package for compatible hoisted deps; this leftover is the
  conflict-nest path for the same version.
  Upstream discussion: https://github.com/jdx/aube/discussions/1293
  Upstream fix: https://github.com/jdx/aube/pull/1296

- [`hoisted-workspace-auto-install-freshness`](hoisted-workspace-auto-install-freshness)
  (observed with aube `1.40.0`, fixed in aube `1.41.0`, retested on
  `1.41.0`): after a valid hoisted workspace install, a
  member-only direct dependency lives at the workspace-root
  `node_modules/<dep>` and the package-local
  `packages/<pkg>/node_modules/<dep>` slot is intentionally absent. Node
  resolves the dependency through the root placement. `aube run` and
  `aube exec` used to report `installed entry missing` for that absent slot
  and reinstall on every invocation. Aube `1.41.0` records the actual
  ancestor-visible placement, so repeated commands remain warm.
  `AUBE_NO_AUTO_INSTALL=1` and
  `--no-install` skip the check. Direct `aube run ok` reproduces without
  aubeshim when the workspace or env keeps `node-linker=hoisted`; without
  that, the first auto-install rewrites the tree to isolated and the
  second run stays warm. Distinct from
  [`hoisted-workspace-shared-dep-realpath`](hoisted-workspace-shared-dep-realpath)
  (shared package-root identity, fixed in aube `1.38.1`). Native pnpm
  `11.21.0` uses the same root-only hoisted placement.
  Docs: https://aube.jdx.dev/package-manager/install,
  https://aube.jdx.dev/package-manager/node-modules,
  https://aube.jdx.dev/package-manager/workspaces,
  https://aube.jdx.dev/settings/#setting-aubenoautoinstall
  Related:
  [#1242 hoisted-shared-realpath](https://github.com/jdx/aube/discussions/1242) /
  [#1243 workspace-hoisted-planner](https://github.com/jdx/aube/pull/1243)
  made the package-local slot intentionally absent;
  [#188 install-entry-freshness](https://github.com/jdx/aube/pull/188) added
  the warm-path
  `direct_entries` existence check.
  Upstream discussion: https://github.com/jdx/aube/discussions/1292
  Upstream fix: https://github.com/jdx/aube/pull/1295

- [`npm-lock-add-reresolve`](npm-lock-add-reresolve) (observed with aube
  `1.38.1`, fixed in aube `1.41.0`, retested on `1.41.0`): `aube install`
  treats a fresh npm `package-lock.json` as up to date, but `aube add` of a
  named spec used to re-resolve unrelated hoisted
  versions. The fixture pins `jest-config@29.7.0` exactly. The lockfile was
  produced by npm `11.17.0` with `npm install --ignore-scripts
  --package-lock-only --no-audit --no-fund`; npm `12.0.2` left that lock
  byte-identical. npm hoists `camelcase@5.3.1` and nests `camelcase@6.3.0`
  under `jest-validate`. Real `npm install is-number@7.0.0` only promotes
  that already-transitive package. `aube add is-number@7.0.0` hoists
  `camelcase` to `6.3.0`. The same rewrite happens for
  `aube add jest-config@29.7.0` (already the exact pin) and
  `aube install --fix-lockfile`, with either isolated or hoisted
  `AUBE_NODE_LINKER`. Aube `1.41.0` preserves reachable top-level npm
  placements when rewriting the lockfile, so the unrelated camelcase choice
  stays unchanged. Smaller trees (`express`, `esbuild`, a two-package
  `camelcase` pair) did not reproduce the hoist.
  Docs: https://aube.jdx.dev/package-manager/install,
  https://aube.jdx.dev/package-manager/lockfiles,
  https://aube.jdx.dev/package-manager/dependencies
  Related:
  [#1155 lock-diff-scope](https://github.com/jdx/aube/discussions/1155)
  expected an `add` lock diff to contain only the new package;
  [#938 optional-native-recording](https://github.com/jdx/aube/discussions/938)
  is optional-native
  recording, not unrelated version hoists;
  [`npm-lock-missing-entry`](npm-lock-missing-entry) is a different
  `--fix-lockfile` missing-path case.
  Upstream discussion: https://github.com/jdx/aube/discussions/1286
  Upstream fix: https://github.com/jdx/aube/pull/1287

- [`hoisted-workspace-shared-dep-realpath`](hoisted-workspace-shared-dep-realpath)
  (observed with aube `1.37.0`, fixed in aube `1.38.1`, retested on `1.38.1`):
  in a two-package workspace that pins the same version of a dependency in both
  packages, `aube install --node-linker=hoisted` used to materialize distinct
  real directories at each package's `node_modules/<dep>`, so Node and bundlers
  loaded multiple module instances. The linker now plans one workspace-wide
  hoisted tree; with default `hoistingLimits=none`, compatible deps hoist to a
  single workspace-root placement. Package-local `node_modules/<dep>` slots may
  be absent; the repro asserts identity with
  `require.resolve(..., { paths })` from each importer. First seen on a large
  Expo/Metro monorepo that forced hoisted for in-tree resolve and ended up with
  many physical `effect` trees under workspace packages.
  Docs: https://aube.jdx.dev/package-manager/node-modules,
  https://aube.jdx.dev/package-manager/workspaces
  Upstream discussion: https://github.com/jdx/aube/discussions/1242
  Upstream fix: https://github.com/jdx/aube/pull/1243

- [`pnpm-patch-edit-stale-lock-hash`](pnpm-patch-edit-stale-lock-hash)
  (observed with aube `1.36.0`, fixed in aube `1.37.0`, retested on `1.37.0`):
  after a declared patch file's content changed, frozen installs used to accept
  the stale lockfile silently while a plain install applied the new patch but
  retained the old content hash. Frozen installs now reject the drift with
  `ERR_AUBE_LOCKFILE_CONFIG_MISMATCH`, and a plain install applies the revised
  patch and refreshes the lockfile hash.
  Upstream discussion: https://github.com/jdx/aube/discussions/1197
  Upstream fix: https://github.com/jdx/aube/pull/1196

- [`pnpm-patch-commit-existing-patch`](pnpm-patch-commit-existing-patch)
  (observed with aube `1.36.0`, fixed in aube `1.37.0`, retested on `1.37.0`):
  `aube patch-commit` for an already-patched package used to replace the
  declared patch with an incremental-only diff that could not apply to pristine
  package contents. It now reuses the existing patch path and composes the old
  patch with the new edits, producing a patch that survives a clean reinstall.
  Upstream discussion: https://github.com/jdx/aube/discussions/1195
  Upstream fix: https://github.com/jdx/aube/pull/1196

- [`pnpm-user-npmrc-allowbuilds-read-only`](pnpm-user-npmrc-allowbuilds-read-only)
  (observed with aube `1.32.0` and `1.34.0`, fixed in aube `1.35.0`, retested
  on `1.36.0`): `aube config get allowBuilds` used to report a value from the
  user-level `~/.npmrc` that `aube install` then ignored, so the documented way
  to check the setting confirmed a configuration that had no effect. The same
  allowlist in `package.json#aube.allowBuilds` was always honored. Install only
  trusts project-scoped `allowBuilds` by design; the fix filters `.npmrc` rows
  from config inspection for settings that do not declare that source, so
  `config get` now returns `undefined` for a user `.npmrc` allowlist.
  Follow-up to the write half raised in
  [#617](https://github.com/jdx/aube/discussions/617).
  Upstream discussion: https://github.com/jdx/aube/discussions/1158
  Upstream fix: https://github.com/jdx/aube/pull/1159

- [`pnpm-filter-add-prunes-platform-optionals`](pnpm-filter-add-prunes-platform-optionals)
  (observed with aube `1.32.0` and `1.34.0`, fixed in aube `1.35.0`, retested
  on `1.36.0`): in a workspace whose `supportedArchitectures` lists include
  `current`, `aube --filter <pkg> add` used to drop every foreign-platform
  optional dependency from a pnpm lockfile (45 esbuild platform entries to 0 on
  `1.34.0`). Portable lockfiles now keep every platform variant while
  fetch/link still honor `supportedArchitectures`. The repro passes
  `--allow-low-downloads` so aube's post-1.35 similar-name gate on `is-odd`
  does not block the add under test.
  Related to [#938](https://github.com/jdx/aube/discussions/938) /
  [#942](https://github.com/jdx/aube/pull/942) for the npm lockfile path.
  Upstream discussion: https://github.com/jdx/aube/discussions/1155
  Upstream fix: https://github.com/jdx/aube/pull/1156

- [`pnpm-file-dep-stale-store`](pnpm-file-dep-stale-store) (observed with
  aube `1.26.0`, fixed in aube `1.28.0`): a settled workspace with a nested
  `file:./modules/...` dependency kept serving a stale store copy under
  `node_modules/.aube/<name>@file+<path-hash>/` after the source directory
  changed on disk. Native pnpm re-added and refreshed the installed content
  from the same state. Aube now fingerprints local directory dependency
  contents before taking the warm "Already up to date" path.
  Docs: https://aube.jdx.dev/package-manager/dependencies,
  https://aube.jdx.dev/pnpm-users
  Upstream discussion: https://github.com/jdx/aube/discussions/1030
  Upstream fix: https://github.com/jdx/aube/pull/1034
- [`pnpm-patch-reresolve-drop`](pnpm-patch-reresolve-drop) (observed with
  aube `1.26.0`, fixed in aube `1.28.0`): a non-frozen `aube install` that
  re-resolved because of unrelated manifest drift lost pnpm-compatible patch
  metadata for a still-declared patch. Later aube builds restored the top-level
  entry but still dropped `(patch_hash=...)` identities, so a subsequent native
  pnpm `--frozen-lockfile` install failed. Aube now preserves or derives pnpm
  patch hashes on re-resolve.
  Docs: https://aube.jdx.dev/package-manager/lockfiles,
  https://aube.jdx.dev/pnpm-users
  Upstream discussion: https://github.com/jdx/aube/discussions/1029
  Upstream fix: https://github.com/jdx/aube/pull/1035
- [`pnpm-patch-stale-lock-path`](pnpm-patch-stale-lock-path) (observed with
  aube `1.26.0`, also reproduced on `1.25.2`, fixed in aube `1.27.0`): a
  non-frozen `aube install` failed reading a stale `patchedDependencies` path
  from the committed lockfile after the workspace moved to a different patch
  key and deleted the old patch file. Native pnpm re-resolved and applied the
  current patch from the same state. Fresh re-resolutions now replace the
  overlaid patch map with the current workspace declarations.
  Docs: https://aube.jdx.dev/package-manager/lockfiles,
  https://aube.jdx.dev/pnpm-users
  Upstream discussion: https://github.com/jdx/aube/discussions/1019
  Upstream fix: https://github.com/jdx/aube/pull/1022
- [`pnpm-patch-plain-unified-diff`](pnpm-patch-plain-unified-diff) (observed
  with aube `1.26.0`, also reproduced on `1.25.2`, fixed in aube `1.27.0`):
  aube's patch applier only recognized file sections introduced by a
  `diff --git` header line. Plain unified diffs starting with `---` / `+++`
  failed with `patch section missing file path`. Native pnpm applied the same
  patch from the same `patchedDependencies` entry. Aube now accepts plain
  unified diffs as well.
  Docs: https://aube.jdx.dev/cli/patch-commit,
  https://aube.jdx.dev/pnpm-users
  Upstream discussion: https://github.com/jdx/aube/discussions/1018
  Upstream fix: https://github.com/jdx/aube/pull/1021
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
  (observed with aube `1.15.0`, still present with aube `1.37.0` in default
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
  Mitigated by `aube install --node-linker=hoisted`, and by aubeshim
  for npm-shaped local commands, which runs npm-shimmed aube invocations with
  `AUBE_NODE_LINKER=hoisted` unless the caller already selected a node linker.
  Upstream discussion: https://github.com/jdx/aube/discussions/754
- [`install-omit-optional`](install-omit-optional) (observed with aube
  `1.14.1`, still present with aube `1.37.0`): aube rejects
  `aube install --omit optional` with an unexpected argument error. This blocks
  npm/Bun-compatible production install commands that use `--omit optional`;
  aube's documented equivalent is `--no-optional`. Mitigated in aubeshim,
  which translates npm/Bun `--omit optional` to aube `--no-optional`
  and npm/Bun `--omit dev` to aube `--prod`.
  Docs: https://aube.jdx.dev/package-manager/install

Each case has a `repro.sh` script that exits zero when aube behaves correctly
and non-zero when the issue is observed.
