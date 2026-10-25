# Relocated lockfile workspace importers

Observed with aube 2.8.2. This case checks two independent failures:

- A workspace writes a relocated aube/pnpm lockfile, then rejects its own
  `apps/app` importer on a clean frozen install.
- A project moves a native npm or Bun lockfile into `locks/`, then aube rejects
  its implicit root importer `.` as foreign to the project key `..`.

The only dependency is `is-number@7.0.0`. pnpm 12.14.0 is the workspace
control; npm 11.6.2 and Bun generate the native-format fixtures. The script
checks installed runtime behavior and frozen lockfile byte equality. Logs,
lockfiles, modules, stores and caches remain under ignored `.repro-work/`.

Point `AUBE_BIN`, `PNPM_BIN`, `NPM_BIN` and `BUN_BIN` at real executables and
run `./repro.sh`. Exit 0 means all checks pass, 1 means the bug is observed,
and 2 means a required tool or native control failed.
