const fs = require("node:fs");
const [kind, seed, result] = process.argv.slice(2);
const before = JSON.parse(fs.readFileSync(seed)).packages;
const after = JSON.parse(fs.readFileSync(result)).packages;

if (kind === "bundle") {
    const key = "node_modules/@tailwindcss/oxide-wasm32-wasi";
    for (const field of ["bundleDependencies", "dependencies"]) {
        if (!before[key]?.[field]) throw new Error(`seed lacks ${field}`);
        if (JSON.stringify(before[key][field]) !== JSON.stringify(after[key]?.[field])) {
            console.log(`${key}: ${field} changed to ${JSON.stringify(after[key]?.[field])}`);
        }
    }
} else if (kind === "nested") {
    for (const name of ["tr46", "webidl-conversions"]) {
        const key = `node_modules/data-urls/node_modules/${name}`;
        if (!before[key]) throw new Error(`seed lacks ${key}`);
        if (!after[key]) console.log(`${key}: removed`);
        else if (after[key].version !== before[key].version) console.log(`${key}: version changed`);
    }
} else {
    throw new Error(`unknown fixture: ${kind}`);
}
