#!/usr/bin/env node
// Minimal npm-compatible registry that always reports publishedAt = now.
// Used so the repro stays durable without depending on a same-day public publish.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";

const port = Number(process.env.PORT || 0);
const tarballPath = process.env.TARBALL_PATH;
const integrity = process.env.TARBALL_INTEGRITY;
const shasum = process.env.TARBALL_SHASUM;
const pkgName = process.env.PKG_NAME || "fresh-pkg";
const pkgVersion = process.env.PKG_VERSION || "1.0.0";

if (!tarballPath || !integrity || !shasum) {
  console.error(
    "mock-registry.mjs requires TARBALL_PATH, TARBALL_INTEGRITY, TARBALL_SHASUM",
  );
  process.exit(2);
}

const tarballName = path.basename(tarballPath);

function packument(host) {
  const now = new Date().toISOString();
  const tarballUrl = `http://${host}/fresh-pkg/-/${tarballName}`;
  const versionMeta = {
    name: pkgName,
    version: pkgVersion,
    main: "index.js",
    dist: {
      integrity,
      shasum,
      tarball: tarballUrl,
    },
  };
  return {
    name: pkgName,
    "dist-tags": { latest: pkgVersion },
    versions: { [pkgVersion]: versionMeta },
    time: {
      created: now,
      modified: now,
      [pkgVersion]: now,
    },
  };
}

const server = http.createServer((req, res) => {
  const host = req.headers.host || `127.0.0.1:${port}`;
  const url = req.url || "/";
  if (url === "/fresh-pkg" || url.startsWith("/fresh-pkg?")) {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(packument(host)));
    return;
  }
  if (
    url === `/fresh-pkg/${pkgVersion}` ||
    url.startsWith(`/fresh-pkg/${pkgVersion}?`)
  ) {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(packument(host).versions[pkgVersion]));
    return;
  }
  if (url === `/fresh-pkg/-/${tarballName}`) {
    const body = fs.readFileSync(tarballPath);
    res.writeHead(200, {
      "content-type": "application/octet-stream",
      "content-length": body.length,
    });
    res.end(body);
    return;
  }
  res.writeHead(404, { "content-type": "text/plain" });
  res.end("not found\n");
});

server.listen(port, "127.0.0.1", () => {
  const addr = server.address();
  if (!addr || typeof addr === "string") {
    console.error("failed to bind mock registry");
    process.exit(2);
  }
  // Parent reads the bound port from stdout (and optional PORT_FILE).
  const line = String(addr.port) + "\n";
  process.stdout.write(line);
  if (process.env.PORT_FILE) {
    fs.writeFileSync(process.env.PORT_FILE, line);
  }
});
