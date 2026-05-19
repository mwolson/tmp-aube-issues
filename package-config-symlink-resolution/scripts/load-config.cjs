const fs = require("node:fs");
const path = require("node:path");
const requireFromString = require("require-from-string");

const symlinkPath = path.join(
  process.cwd(),
  "node_modules",
  "config-owner",
  "react-native.config.js",
);
const realPath = fs.realpathSync(symlinkPath);

const symlinkResult = tryLoadConfig(symlinkPath);
const realPathResult = tryLoadConfig(realPath);

console.log(`symlink path: ${symlinkPath}`);
console.log(`real path:    ${realPath}`);

if (!symlinkResult.ok && realPathResult.ok) {
  console.error("");
  console.error("Observed issue:");
  console.error(`- Loading through node_modules symlink failed: ${symlinkResult.error.message}`);
  console.error(
    `- Loading through fs.realpathSync(...) succeeded and resolved ${realPathResult.value.resolvedDependency}`,
  );
  process.exit(1);
}

if (!symlinkResult.ok) {
  console.error("");
  console.error(`Both config loads failed. Symlink error: ${symlinkResult.error.message}`);
  console.error(`Realpath error: ${realPathResult.error?.message ?? "none"}`);
  process.exit(2);
}

console.log("");
console.log("Config loaded through node_modules symlink successfully.");
console.log(`Resolved dependency: ${symlinkResult.value.resolvedDependency}`);

function tryLoadConfig(filename) {
  try {
    const contents = fs.readFileSync(filename, "utf8");
    return {
      ok: true,
      value: requireFromString(contents, filename),
    };
  } catch (error) {
    return {
      ok: false,
      error,
    };
  }
}
