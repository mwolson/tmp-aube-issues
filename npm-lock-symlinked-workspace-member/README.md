# aube cannot parse npm's non-installed entries outside node_modules

npm 10 and npm 11 up to 11.14.1 write `"extraneous": true` entries outside
`node_modules` in two ordinary workspace situations:

- `symlinked`: a member folder is a symlink (`packages/b -> ../../ext/b`).
  Next to the member's own `packages/b` entry and `node_modules/b` link, npm
  records the symlink's real location:
  `"../ext/b": {"version": "1.0.0", "extraneous": true}`.
- `removed`: a member folder was deleted after the lockfile was written. npm
  keeps its entry as `"packages/b": {"version": "1.0.0", "extraneous": true}`.

A third shape comes from every npm version, including current ones:

- `delisted-parent`: `packages/b` is removed from `workspaces` while its
  subfolder `packages/b/inner` stays a member. npm keeps
  `"packages/b": {"version": "1.0.0"}` without the extraneous flag, because
  it is the folder above a live member (npm 11.20.0 adds `dev`, `optional` and
  `peer` flags to the same entry).

None of these entries carries `name`, and its key has no `node_modules/`
segment, so aube stops with `ERR_AUBE_LOCKFILE_PARSE ... could not determine
package name for '../ext/b'` (or `'packages/b'`) on every command that reads
the lockfile, including `aube install --frozen-lockfile` and `aube add`. npm
11.6.2's `npm ci` accepts all three lockfiles and leaves them unchanged.

npm 11.15.0 and later no longer write the extraneous entries
(`@npmcli/arborist` 9.6.0 skips extraneous nodes outside `node_modules` when
saving), so the first two shapes come from older npm versions, which many
projects still pin. npm 11.20.0 still writes and keeps the third.

The case runs real `npm ci` as the control, then `aube install
--frozen-lockfile` (which must pass, leave the lockfile unchanged and, for the
symlinked member, let the root `require("b")`). Finally it adds
`is-number@7.0.0` to the root with npm 11.6.2 and with `aube add`, and
compares the two lockfiles. npm 11.6.2 keeps these entries when it rewrites
the lockfile.

Fixtures: `fixture/*/package-lock.json` were written by npm 11.6.2 on Node
22.22.0 with `npm install --package-lock-only --ignore-scripts --no-audit
--no-fund`, without edits. `symlinked` was written with the
`packages/b -> ../../ext/b` symlink in place, which the script recreates at
runtime. `removed` was written with members `a` and `b`, then rewritten with
the same command after `packages/b` was deleted. `delisted-parent` was
written with `workspaces` set to `["packages/b", "packages/b/inner"]`, then
rewritten with the same command after `workspaces` became
`["packages/b/inner"]`.

Run with a real npm 11.6.2 and Node 22.22.0 first on PATH:

```sh
AUBE_BIN=/path/to/aube NPM_BIN=/path/to/npm-11.6.2 ./repro.sh
```

`REPRO_WORK_DIR` moves the generated projects and logs (default
`.repro-work/`); caches and stores stay inside the run directory. The add step
fetches `is-number` from the registry. Exit 2 means an environment or control
failure.

Observed 2026-10-26 with `aube 2.8.3 linux-x64 (2026-10-25)` (released), with
upstream main `3c226195`, and with fork `2.8.3+mwolson.3`: exit 1, with the
frozen install failing at the parse step in all three scenarios.

Fork fix in
[#25 npm-lock-symlinked-workspace-member](https://github.com/mwolson/aube/pull/25):
exit 0 with `aube 2.8.3+mwolson.4 linux-x64 (2026-10-26)` and `2.8.3+mwolson.5`.
