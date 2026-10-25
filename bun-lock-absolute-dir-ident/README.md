# Absolute directory identifiers in bun.lock

Run with a real Bun binary, such as Bun 1.4.3:

```sh
AUBE_BIN=/path/to/aube BUN_BIN=/path/to/real/bun ./repro.sh
```

The generated tarball `host` requires one local `child` directory through an
absolute `file:` dependency. The project opts out of `block-exotic-subdeps`.
Bun writes a relative folder identifier such as `child@file:assets/child`, while
aube's writer originally emitted an absolute identifier. Bun refuses that
absolute identifier during a hoisted frozen install.

Released aube 2.8.2 fails this case earlier during resolution, before writing a
lockfile. With the tarball absolute-child resolver fix, the case reaches and
isolates the writer failure. Direct absolute directory dependencies already
work with released aube 2.8.2 and Bun.

Bun 1.4.3 accepts its native lockfile with either linker, but its own hoisted
layout omits this transitive directory at runtime. The script checks hoisted
lock acceptance and isolated runtime separately. A passing result does not
claim to fix Bun's hoisted runtime layout.

The script exits 0 when aube's folder identifier is accepted and isolated
runtime works, 1 when the aube case fails, and 2 when a tool or native control
fails. Generated tarballs, projects, logs, stores, and caches stay under
`.repro-work/`.
