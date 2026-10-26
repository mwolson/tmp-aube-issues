# A new npm workspace member is missing from, or written differently into, package-lock.json

The fixture is a one-member npm workspace whose `package-lock.json` npm 11.6.2
wrote (`npm install --package-lock-only --ignore-scripts --no-audit
--no-fund`, Node 22.22.0, no edits). The case adds one more member, runs
`npm install --package-lock-only` in one copy and `aube install` in another,
and compares the member's lockfile entries. Each lockfile then goes through a
real `npm ci`.

- Member `b` has no dependencies. aube reports the install as up to date and
  writes nothing for it, so `npm ci` fails with
  `Missing: b@1.0.0 from lock file`. npm writes `"b": {"version": "1.0.0"}`
  and the `node_modules/b` link.
- Member `c` has one dependency and declares `os` and `cpu`. aube writes it,
  but adds `"name": "c"` and leaves out `os` and `cpu`, which npm copies from
  the member's `package.json`. `npm ci` accepts both; npm restores its shape on
  the next write.

Run with a real npm 11.6.2 and Node 22.22.0 first on PATH:

```sh
AUBE_BIN=/path/to/aube NPM_BIN=/path/to/npm-11.6.2 ./repro.sh
```

`REPRO_WORK_DIR` moves the generated projects and logs (default
`.repro-work/`); caches and stores stay inside the run directory. Exit 2 means
an environment or control failure.

Observed 2026-10-25 with `aube 2.8.3 linux-x64 (2026-10-25)` on upstream main
`3c226195` and with the released `2.8.3`: exit 1 for both members.
