# npm-lock-optional-orphan

Existing entry under test: `node_modules/@rolldown/binding-wasm32-wasi/node_modules/@emnapi/wasi-threads`.

The fixture was produced by npm 11.6.2 with Node 26.12.1 using:

```sh
npm install --package-lock-only --ignore-scripts --no-audit --no-fund
```

```sh
npm install @emnapi/core@1.11.2 --save-exact --package-lock-only --ignore-scripts --no-audit --no-fund
```

The initial manifest has only these declarations:

```json
{"dependencies":{"@emnapi/core":"1.10.0","@napi-rs/wasm-runtime":"0.2.12"},"optionalDependencies":{"@rolldown/binding-wasm32-wasi":"1.0.3"}}
```

The optional fixture starts with `@emnapi/core` pinned to `1.10.0`, then the second command updates it to `1.11.2`. npm itself leaves the nested optional `wasi-threads@1.2.1` while removing the nested `core@1.10.0`. No lockfile entries were hand-edited.

Run with npm 11.6.2 as `NPM_BIN` and the aube binary as `AUBE_BIN`.
The script adds `is-number@7.0.0`, checks that npm keeps the target entry,
then checks aube's entry and runs npm `ci --ignore-scripts` on both results.
Exit status: 0 correct, 1 bug observed, 2 environment or control failure.
