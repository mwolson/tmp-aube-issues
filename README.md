# aube issue repros

Minimal repros for aube compatibility issues found while testing
existing npm and Bun projects.

## Open

- [`bun-patched-dependencies`](bun-patched-dependencies) (observed with aube
  `1.14.1`): aube installs
  from Bun's text `bun.lock`, but it does not apply Bun's top-level
  `patchedDependencies` manifest field. Native Bun applies the patch from the
  same manifest and lockfile. Aube documents patch support through
  `aube.patchedDependencies` / `pnpm.patchedDependencies`, but the Bun rollout
  docs do not mention Bun's top-level field.
  Docs: https://aube.en.dev/package-manager/configuration,
  https://aube.en.dev/bun-users
- [`yarn-react-scripts-workbox-transitive`](yarn-react-scripts-workbox-transitive)
  (observed with aube `1.14.1`): aube installs from a Yarn v1 `yarn.lock`, but
  the materialized dependency tree does not make `workbox-build`'s declared
  dependency
  `@apideck/better-ajv-errors` resolvable from `workbox-build`. Native Yarn
  v1.22.22 installs the same lockfile with that dependency resolvable. This was
  reduced from a `react-scripts@5.0.0` build failure through
  `workbox-webpack-plugin@6.6.1`.
  Docs: https://aube.en.dev/package-manager/lockfiles,
  https://aube.en.dev/troubleshooting

## Fixed

- [`npm-lock-missing-entry`](npm-lock-missing-entry) (observed with aube
  `1.14.0`, fixed in aube `1.14.1`): aube repairs a stale npm
  `package-lock.json` by adding the root `expo-router` dependency spec,
  but it does not add `packages["node_modules/expo-router"]`. A clean frozen
  aube install then omits `node_modules/expo-router`. The stale npm lock was
  produced by npm `11.14.1` from the same manifest before `expo-router` was
  added, using `npm install --package-lock-only --ignore-scripts --no-audit
  --no-fund`.
  Upstream discussion: https://github.com/endevco/aube/discussions/690
- [`bun-workspace-link`](bun-workspace-link) (observed with aube `1.13.1`,
  fixed in aube `1.14.1`): aube installs from Bun's text `bun.lock`, but a
  workspace dependency symlink inside `packages/app` points to the workspace
  root instead of `packages/contracts`.
  Upstream discussion: https://github.com/endevco/aube/discussions/691

## Mitigated

- [`install-omit-optional`](install-omit-optional) (observed with aube
  `1.14.1`): aube rejects
  `aube install --omit optional` with an unexpected argument error. This blocks
  npm/Bun-compatible production install commands that use `--omit optional`;
  aube's documented equivalent is `--no-optional`. Mitigated in aubeshim
  `0.5.0`, which translates npm/Bun `--omit optional` to aube `--no-optional`
  and npm/Bun `--omit dev` to aube `--prod`.
  Docs: https://aube.en.dev/package-manager/install

Each case has a `repro.sh` script that exits zero when aube behaves correctly
and non-zero when the issue is observed.
