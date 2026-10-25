# Absolute directory target keys in package-lock.json

Run with a real npm binary, such as npm 11.6.2:

```sh
AUBE_BIN=/path/to/aube NPM_BIN=/path/to/real/npm ./repro.sh
```

The fixture has one local package with no dependencies. The script generates an
absolute `file:` specifier for it. Native npm writes a relative linked target
key and `resolved` value, and passes fresh install and clean `npm ci`.

Released aube 2.8.2 instead writes an absolute target key. Its own fresh and
clean frozen installs pass, but npm rejects the lockfile with `EUSAGE`.

The script exits 0 when both tools accept aube's lockfile, 1 when aube's output
fails the checks, and 2 when a tool or native control fails. Generated projects,
logs, stores, and caches stay under `.repro-work/`.
