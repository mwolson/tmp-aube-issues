# npm-lock-frozen-member-drift

`aube install --frozen-lockfile` accepts an npm lockfile that `npm ci` rejects, in
two cases: a workspace member's `name` changes while its folder stays, and a
dependency-free member joins a project that uses `npm-shrinkwrap.json`.

Each scenario seeds the lockfile with real npm 11.6.2, confirms aube's frozen
install accepts the unchanged lockfile, makes the change, and confirms `npm ci`
rejects the result.

```sh
AUBE_BIN=/path/to/aube NPM_BIN=/path/to/npm-11.6.2 ./repro.sh
```
