const fs = require("fs");
const path = require("path");
const { createRequire } = require("module");

function pkgReal(fromFile) {
  const r = createRequire(fromFile);
  const resolved = r.resolve("is-number/package.json");
  return fs.realpathSync(path.dirname(resolved));
}

const app = pkgReal(path.resolve("package.json"));
const rangePkg = createRequire(path.resolve("package.json")).resolve(
  "to-regex-range/package.json",
);
const fromRange = pkgReal(rangePkg);
process.stdout.write(`from app            ${app}\n`);
process.stdout.write(`from to-regex-range ${fromRange}\n`);
process.stdout.write(`same realpath       ${app === fromRange}\n`);
process.exit(app === fromRange ? 0 : 1);
