# dlx allow-build flag

Observed with aube `1.18.0` and pnpm `11.3.0`.

pnpm documents `pnx`, `pnpm dlx`, and `pnpx` as aliases that accept
`--allow-build` to allow named packages to run postinstall scripts during the
temporary install.

Aube supports the `allowBuilds` policy generally and supports
`--allow-build=<pkg>` on `aube add`, but `aube dlx --allow-build=esbuild ...`
currently treats the flag as the package to execute.

Run:

```sh
./repro.sh
```

The script exits zero when aube accepts the pnpm-compatible `dlx` flag and
nonzero when the current parser failure is observed.
