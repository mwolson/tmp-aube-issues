# Native Bun hoisted member-relative tarball

Bun 1.4.3 hoists a member's local tarball as `consumer` while retaining its
member-relative ident `consumer@../../consumer.tgz`. The declaring workspace
is `apps/app`. The root declares React 18; the member declares React 19 and the
consumer, which peers on React 19.

`repro.sh` creates three tiny local tarballs, lets native Bun generate `bun.lock`,
and verifies fresh and clean frozen Bun installs load React 19. It then removes
`node_modules` and asks aube to perform a frozen install from the exact native
lockfile. That must succeed, leave the lockfile unchanged, and load React 19
from the member's consumer.

Set `BUN_BIN` to the real Bun binary and `AUBE_BIN` to the binary being tested.
Exit 0 means correct behavior, 1 means the bug is observed, and 2 means a setup
or native-control failure. All generated files and caches stay in `.repro-work/`.
