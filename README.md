# aube issue repros

Minimal repros for aube compatibility issues found while testing
existing npm and Bun projects.

## Cases

- `npm-lock-missing-entry` (observed with aube `1.13.1`): aube repairs a stale
  npm `package-lock.json` by adding the root `expo-router` dependency spec,
  but it does not add `packages["node_modules/expo-router"]`. A clean frozen
  aube install then omits `node_modules/expo-router`.
  Upstream discussion: https://github.com/endevco/aube/discussions/690
- `bun-workspace-link` (observed with aube `1.13.1`): aube installs from Bun's
  text `bun.lock`, but a workspace dependency symlink inside `packages/app`
  points to the workspace root instead of `packages/contracts`.
  Upstream discussion: https://github.com/endevco/aube/discussions/691

Each case has a `repro.sh` script that exits zero when aube behaves correctly
and non-zero when the issue is observed.
