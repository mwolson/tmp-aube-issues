# New npm lock entries omit hasInstallScript

Starting from an empty npm project, `aube add core-js@3.46.0` writes a new
`package-lock.json` entry without `hasInstallScript: true`. Real npm ci succeeds
but silently skips core-js's postinstall. The npm add control writes the flag,
and npm ci then runs the script. No lifecycle script is run by aube in this
case; the observation concerns npm consuming aube's lockfile.

The root-only fixture was generated with npm 11.6.2:

```sh
npm install --package-lock-only --ignore-scripts --no-audit --no-fund
```

Run with real binaries, avoiding package-manager shims:

```sh
AUBE_BIN=/path/to/aube NPM_BIN=/path/to/real/npm ./repro.sh
```

Tested on Linux x64 with npm 11.6.2: aube `2.8.2 linux-x64 (2026-10-23)`
exits 1 (flag false, postinstall skipped); `2.8.2+mwolson.1 linux-x64
(2026-10-24)` exits 0 (flag true, postinstall runs). The npm control runs the
postinstall in both runs. The script explicitly enables npm lifecycle scripts
and observes npm's info log. All caches and stores stay in `.repro-work/`.
Exit 2 means an environment or control failure.
