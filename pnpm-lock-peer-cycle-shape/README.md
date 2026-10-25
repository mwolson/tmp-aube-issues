# Peer-cycle suffixes and retained provider contexts

An unrelated `aube add` changes snapshot keys that native pnpm retains. This
extends the alias and out-of-range optional-peer cases in
[#1823 pnpm-lock-peer-suffix-shape](https://github.com/aubepkg/aube/discussions/1823).

Run with Python 3, aube, and a real pnpm binary:

```sh
PNPM_BIN=/path/to/real/pnpm AUBE_BIN=/path/to/aube ./repro.sh
```

Exit 0 means the snapshot keys match pnpm, exit 1 means the difference was
observed, and exit 2 means a prerequisite or control failed. The runner uses a
temporary loopback registry serving only the manifests in
`fixture/packages.json`. It generates package tarballs in memory, writes all
projects, logs, stores, and caches beneath `.repro-work/`, and stops its server
before exiting. It needs no public registry packages or Python dependencies.

## Cycle cut

The root depends only on `cycle-consumer@1.0.0`. That package peers on
`cycle-host`, which peers on `cycle-plugin`, which peers on `cycle-host`.
pnpm auto-installs the providers. Every package version is 1.0.0.

After seeding with native `pnpm install --lockfile-only --ignore-scripts`, the
runner compares native `pnpm add extra@1.0.0 --lockfile-only --ignore-scripts`
with `aube add extra@1.0.0 --ignore-scripts` in separate copies of that seed.
The additional package is also served locally.

```text
pnpm 11.10.0 / 12.14.0:
  cycle-consumer@1.0.0(cycle-host@1.0.0)
aube 2.8.2:
  cycle-consumer@1.0.0(cycle-host@1.0.0(cycle-plugin@1.0.0))
```

The host and plugin themselves have identical keys in both outputs. The
difference occurs when an outside consumer names a provider in that peer cycle.
Removing either mutual peer declaration eliminates the difference. Removing the
outside consumer also eliminates it, so the fixture retains three package names
and only one initial root dependency.

The same graph runs again with `peersSuffixMaxLength: 1`, forcing a short hash:

```text
pnpm 11.10.0 / 12.14.0:
  cycle-consumer@1.0.0(076b888d571dde1717a49649afd28f85)
aube 2.8.2:
  cycle-consumer@1.0.0(8727237358689001e387cbafa03f840a)
```

This demonstrates the cycle-rendering input difference behind the additional
Expo suffix-hash churn found in pingdotgg/t3code, without installing Expo.

## Provider choice

`provider-consumer@1.0.0` has optional peer `provider-peer@*`. The root provides
consumer and peer 1.0.0. One workspace member initially provides consumer, peer
2.0.0, and `provider-hidden@1.0.0`, which depends on peer 2.0.0.
`resolvePeersFromWorkspaceRoot: false` isolates the importer contexts.

After native pnpm writes the seed lockfile, the runner removes the member's
direct peer dependency from its manifest. This intentionally leaves that
importer's lockfile stale; peer 2.0.0 remains reachable through hidden. Both tools
then add the unrelated local package at the workspace root.

Native pnpm retains both
`provider-consumer@1.0.0(provider-peer@1.0.0)` and
`provider-consumer@1.0.0(provider-peer@2.0.0)`. Upstream aube keeps only the first
context. This uses three package names, with two versions of the peer, and one
workspace member. It models the lost Drizzle/zod context from pingdotgg/t3code.

## Verification

Tested on Linux with these exact versions:

- `aube 2.8.2 linux-x64 (2026-10-23)`: exit 1 with either pnpm control.
- `aube 2.8.2+mwolson.1 linux-x64 (2026-10-24)`: exit 0 with either control.
- Native pnpm 12.14.0 and 11.10.0: identical snapshot-key controls in all three
  scenarios, including the forced hash and both retained provider contexts.

Both aube versions frozen-install the original native pnpm lockfiles without
changing their bytes. Clean native pnpm frozen installs accept the default-cap
cycle and provider rewrites without changing their lockfiles. The forced-hash
case checks suffixes only after the add: aube separately drops
`settings.peersSuffixMaxLength`, so that setting's frozen round-trip is excluded.
No runtime breakage is claimed here.

The upstream discussion and PR search found the existing suffix report above
and related optional-peer fixes, rather than a separate report covering this
minimal cycle. The official [lockfile documentation](https://aube.en.dev/package-manager/lockfiles.html)
supports reading and writing pnpm v9 files but does not guarantee identical
version selection. These fixtures retain the same versions and demonstrate
snapshot identity churn; neither the lockfile nor node_modules documentation
describes a different cycle-cut rule as intentional behavior.
