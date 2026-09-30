# Missing EOF marker still fails when the hunk has a section heading

Observed with aube 2.6.1 on Linux x64, and unchanged on 2.2.17, 2.3.0 and
2.6.0. Native pnpm 12.8.1 applies every variant below.

This follows up
[`pnpm-patch-missing-eof-marker`](../pnpm-patch-missing-eof-marker) and
[#1515 missing-eof-marker](https://github.com/aubepkg/aube/pull/1515). That fix
retries a failed patch with `\ No newline at end of file` appended after the
final context line. The retry works when the hunk header is bare
(`@@ -2,4 +2,4 @@`). It still fails with `error applying hunk #1` when git wrote
a section heading after the second `@@`
(`@@ -2,4 +2,4 @@ module.exports = 1;`). Git emits a heading for most hunks
that do not start at line 1, so real `pnpm patch-commit` output hits this
often.

## Cause

`apply_with_eof_context` re-renders the parsed patch with diffy's `Display`
before appending the marker. Diffy 0.5.2 renders a hunk heading with an extra
space and an extra newline:

```text
@@ -2,5 +2,5 @@  p

 q
```

The blank line re-parses as an empty context line, so the annotated hunk no
longer matches the file. With a bare header the round trip is exact and the
retry succeeds.

## Run

Requires Bash, Python 3, Node.js, aube, and real pnpm. When using aubeshim, set
`PNPM_BIN` to a real pnpm executable, not the dispatcher:

```bash
PNPM_BIN=/absolute/path/to/real/pnpm ./repro.sh
```

The fixture is a five-line local package whose file has no trailing newline.
Each install gets its own HOME and XDG directories, with no lockfile or
registry dependency. Evidence stays under the ignored `tmp/patch-eof-heading.*`
directory.

- Exit 0: aube applies all three variants with exact output bytes.
- Exit 1: aube rejects at least one variant that pnpm applies.
- Exit 2: a required tool or pnpm control failed.

## Results

| Patch | pnpm 12.8.1 | aube 2.6.1 |
| --- | --- | --- |
| Bare header, missing EOF marker | Pass | Pass |
| Section heading, canonical EOF marker | Pass | Pass |
| Section heading, missing EOF marker | Pass | Fails applying hunk 1 |

```text
failed to apply patch for patch-target@1.0.0:
failed to apply patch for index.js: error applying hunk #1
```

Found installing `react-native-keyboard-controller@1.21.13` with the
pingdotgg/t3code patch, which has 53 headed hunks. Stripping the headings made
aube 2.6.1 install it and produce the patched file with the unterminated last
line preserved.

Upstream discussion:
[#1676 heading-eof-marker](https://github.com/aubepkg/aube/discussions/1676)
