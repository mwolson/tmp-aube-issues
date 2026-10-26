// Minimal npm registry for this case: serves `bundler@1.0.0`, which bundles a
// regular dependency (`inner`) and an optional one (`opt`). Both are also
// published on their own, since Bun resolves bundled names from the registry.
const crypto = require("crypto");
const http = require("http");
const zlib = require("zlib");

function tarEntry(name, body) {
    const data = Buffer.from(body);
    const header = Buffer.alloc(512, 0);
    header.write(name, 0, 100);
    header.write("0000644\0", 100);
    header.write("0000000\0", 108);
    header.write("0000000\0", 116);
    header.write(data.length.toString(8).padStart(11, "0") + "\0", 124);
    header.write("00000000000\0", 136);
    header.write("        ", 148);
    header.write("0", 156);
    header.write("ustar\0" + "00", 257);
    let sum = 0;
    for (const byte of header) sum += byte;
    header.write(sum.toString(8).padStart(6, "0") + "\0 ", 148);
    const pad = Buffer.alloc((512 - (data.length % 512)) % 512, 0);
    return Buffer.concat([header, data, pad]);
}

const manifest = {
    name: "bundler",
    version: "1.0.0",
    dependencies: { inner: "1.0.0" },
    optionalDependencies: { opt: "1.0.0" },
    bundleDependencies: ["inner", "opt"],
};
const tarball = zlib.gzipSync(Buffer.concat([
    tarEntry("package/package.json", JSON.stringify(manifest)),
    tarEntry("package/index.js", "module.exports = require('inner');\n"),
    tarEntry("package/node_modules/inner/package.json", '{"name":"inner","version":"1.0.0"}'),
    tarEntry("package/node_modules/inner/index.js", "module.exports = 'inner ok';\n"),
    tarEntry("package/node_modules/opt/package.json", '{"name":"opt","version":"1.0.0"}'),
    tarEntry("package/node_modules/opt/index.js", "module.exports = 'opt ok';\n"),
    Buffer.alloc(1024, 0),
]));
function publish(pkg, files) {
    const tarball = zlib.gzipSync(Buffer.concat([
        tarEntry("package/package.json", JSON.stringify(pkg)),
        ...Object.entries(files).map(([name, body]) => tarEntry("package/" + name, body)),
        Buffer.alloc(1024, 0),
    ]));
    return {
        tarball,
        integrity: "sha512-" + crypto.createHash("sha512").update(tarball).digest("base64"),
        shasum: crypto.createHash("sha1").update(tarball).digest("hex"),
    };
}

const packages = {
    bundler: { manifest, ...publishTarball(tarball) },
    inner: { manifest: { name: "inner", version: "1.0.0" }, ...publish({ name: "inner", version: "1.0.0" }, { "index.js": "module.exports = 'inner ok';\n" }) },
    opt: { manifest: { name: "opt", version: "1.0.0" }, ...publish({ name: "opt", version: "1.0.0" }, { "index.js": "module.exports = 'opt ok';\n" }) },
};

function publishTarball(tarball) {
    return {
        tarball,
        integrity: "sha512-" + crypto.createHash("sha512").update(tarball).digest("base64"),
        shasum: crypto.createHash("sha1").update(tarball).digest("hex"),
    };
}

const server = http.createServer((req, res) => {
    const base = `http://127.0.0.1:${server.address().port}`;
    const name = req.url.slice(1);
    const tgz = /^([a-z]+)-1\.0\.0\.tgz$/.exec(name);
    if (packages[name]) {
        const pkg = packages[name];
        const version = { ...pkg.manifest, dist: { tarball: `${base}/${name}-1.0.0.tgz`, integrity: pkg.integrity, shasum: pkg.shasum } };
        res.setHeader("content-type", "application/json");
        res.end(JSON.stringify({
            name,
            "dist-tags": { latest: "1.0.0" },
            versions: { "1.0.0": version },
            time: { "1.0.0": "2020-01-01T00:00:00.000Z", modified: "2020-01-01T00:00:00.000Z" },
        }));
    } else if (tgz && packages[tgz[1]]) {
        res.setHeader("content-type", "application/octet-stream");
        res.end(packages[tgz[1]].tarball);
    } else {
        res.statusCode = 404;
        res.end("{}");
    }
});
server.listen(0, "127.0.0.1", () => console.log(server.address().port));
