# Patch without an EOF marker fails under aube but applies under pnpm

Observed with aube 2.2.13 on Linux x64. Native pnpm 11.10.0 and 12.3.4 apply
both variants below.

The target file has two lines and no trailing newline. `change.patch` changes
its first line, with the unterminated second line retained as context. The
patch omits the canonical `\ No newline at end of file` annotation after that
context line.

Adding the missing annotation makes both package managers apply the patch and
preserve the absent trailing newline. The requested compatibility is pnpm's
tolerance for that missing annotation.

## Run

Requires Bash, Python 3, Node.js, aube, and real pnpm. When using aubeshim, set
`PNPM_BIN` to a real pnpm executable, not the dispatcher:

```bash
PNPM_BIN=/absolute/path/to/real/pnpm ./repro.sh
```

The script creates a local package tarball containing only `package.json` and
`index.js`. There are no registry dependencies, peer dependencies, lifecycle
scripts, or committed lockfiles. Each install starts without a lockfile and
gets its own HOME and XDG config, data, cache, and state directories. Neither
package manager reuses the other's installed tree or lockfile.

Evidence stays under the repro repository's ignored `tmp/patch-eof.*` directory.
Set `REPRO_TMP_ROOT` to choose another scratch directory. `AUBE_BIN` can select a
particular aube executable.

The canonical-marker variant runs first as a positive control. The script then
tries the missing-marker variant. Every successful install must export `2` and
preserve the exact expected file bytes, including the absent trailing newline.

- Exit 0: aube applies both variants correctly.
- Exit 1: aube rejects the missing-marker variant with a hunk-application error
  after both pnpm variants and the canonical aube control passed.
- Exit 2: a required tool, control, or another part of the setup failed.

## Results

| Patch | pnpm 11.10.0 | pnpm 12.3.4 | aube 2.2.13 |
| --- | --- | --- | --- |
| Canonical EOF marker | Pass | Pass | Pass |
| Missing EOF marker | Pass | Pass | Fails applying hunk 1 |

```text
failed to apply patch for patch-target@1.0.0:
failed to apply patch for index.js: error applying hunk #1
```

First observed with a patch for `react-native-keyboard-controller@1.21.13`.
The published package contains unterminated JavaScript files, and the patch
omitted four EOF context annotations. Adding those four annotations let aube
2.2.13 complete a clean frozen install from a pnpm-generated lockfile. All 616
package files then matched the output of pnpm applying the original patch.
That registry-package check is separate from this reduced local-tarball case.

Upstream discussion: [#1514 missing-eof-marker](https://github.com/aubepkg/aube/discussions/1514).
The earlier [CRLF patch fix](https://github.com/aubepkg/aube/pull/384) addresses
line-ending normalization.

Relevant docs: [Node modules and pnpm coexistence](https://aube.en.dev/package-manager/node-modules.html),
[lockfiles](https://aube.en.dev/package-manager/lockfiles.html).
