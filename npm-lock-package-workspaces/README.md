# npm-lock-package-workspaces

Existing entry under test: `node_modules/vitefu`.

The fixture was produced by npm 11.6.2 with Node 26.12.1 using:

```sh
npm install --package-lock-only --ignore-scripts --no-audit --no-fund
```

Run with npm 11.6.2 as `NPM_BIN` and the aube binary as `AUBE_BIN`.
The script adds `is-number@7.0.0`, checks that npm keeps the target entry,
then checks aube's entry and runs npm `ci --ignore-scripts` on both results.
Exit status: 0 correct, 1 bug observed, 2 environment or control failure.
