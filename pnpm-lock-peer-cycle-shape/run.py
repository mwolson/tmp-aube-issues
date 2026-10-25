import base64
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parent
WORK = ROOT / ".repro-work"
AUBE = os.environ["AUBE_BIN"]
PNPM = os.environ["PNPM_BIN"]


def main():
    print("aube:", version(AUBE), flush=True)
    print("pnpm:", version(PNPM), flush=True)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Registry)
    server.artifacts = registry_artifacts(server.server_port)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    failed = False
    try:
        for case in ("cycle", "cycle-hashed", "provider"):
            seed = WORK / (case + "-seed")
            write_seed(seed, case, server.server_port)
            run(seed, PNPM, "install", "--lockfile-only", "--ignore-scripts")
            frozen = WORK / (case + "-original-frozen")
            shutil.copytree(seed, frozen)
            before = (frozen / "pnpm-lock.yaml").read_bytes()
            run(frozen, AUBE, "install", "--frozen-lockfile", "--ignore-scripts")
            if (frozen / "pnpm-lock.yaml").read_bytes() != before:
                raise RuntimeError("aube changed the original frozen pnpm lockfile")
            print(case + ": original pnpm lockfile frozen by aube: unchanged", flush=True)
            if case == "provider":
                manifest = seed / "packages/two/package.json"
                data = json.loads(manifest.read_text())
                del data["dependencies"]["provider-peer"]
                manifest.write_text(json.dumps(data, indent=2) + "\n")
            control = WORK / (case + "-pnpm")
            actual = WORK / (case + "-aube")
            shutil.copytree(seed, control)
            shutil.copytree(seed, actual)
            flags = ["--workspace-root"] if case == "provider" else []
            run(control, PNPM, "add", "extra@1.0.0", *flags,
                "--lockfile-only", "--ignore-scripts")
            expected = snapshot_keys(control)
            verify_control(case, expected)
            print(case + ": pnpm add snapshot keys: " + json.dumps(expected), flush=True)
            run(actual, AUBE, "add", "extra@1.0.0", *(["-W"] if flags else []), "--ignore-scripts")
            observed = snapshot_keys(actual)
            print(case + ": aube add snapshot keys: " + json.dumps(observed), flush=True)
            if observed != expected:
                failed = True
            if case != "cycle-hashed":
                clean = WORK / (case + "-rewritten-frozen")
                shutil.copytree(actual, clean, ignore=shutil.ignore_patterns("node_modules", "*.log"))
                before = (clean / "pnpm-lock.yaml").read_bytes()
                run(clean, PNPM, "install", "--frozen-lockfile", "--ignore-scripts")
                if (clean / "pnpm-lock.yaml").read_bytes() != before:
                    raise RuntimeError("pnpm changed the aube lockfile under frozen install")
                print(case + ": clean pnpm frozen install of aube rewrite: pass", flush=True)
        print("failed: aube rewrites pnpm peer-cycle/provider snapshot keys" if failed
              else "pass: aube snapshot keys match native pnpm", flush=True)
        return 1 if failed else 0
    finally:
        server.shutdown()
        server.server_close()


def version(binary):
    return subprocess.check_output([binary, "--version"], text=True).strip()


def run(directory, binary, *args):
    log = directory / (Path(binary).name + "-" + args[0] + ".log")
    with log.open("w") as output:
        result = subprocess.run([binary, *args], cwd=directory, stdout=output,
                                stderr=subprocess.STDOUT, timeout=120)
    if result.returncode:
        raise RuntimeError(f"{Path(binary).name} {' '.join(args)} exited {result.returncode}; see {log}")


def write_seed(directory, case, port):
    directory.mkdir()
    if case.startswith("cycle"):
        deps = {"cycle-consumer": "1.0.0"}
        config = "peersSuffixMaxLength: 1\n" if case.endswith("hashed") else ""
    else:
        deps = {"provider-consumer": "1.0.0", "provider-peer": "1.0.0"}
        config = "packages:\n  - packages/*\nresolvePeersFromWorkspaceRoot: false\n"
        member = directory / "packages/two"
        member.mkdir(parents=True)
        (member / "package.json").write_text(json.dumps({"name": "two", "dependencies": {
            "provider-consumer": "1.0.0", "provider-hidden": "1.0.0", "provider-peer": "2.0.0"
        }}, indent=2) + "\n")
    (directory / "package.json").write_text(json.dumps({"private": True, "dependencies": deps}, indent=2) + "\n")
    (directory / ".npmrc").write_text(f"registry=http://127.0.0.1:{port}/\n")
    (directory / "pnpm-workspace.yaml").write_text(config)


def snapshot_keys(directory):
    # These fixtures use plain unquoted keys and have no second YAML document.
    text = (directory / "pnpm-lock.yaml").read_text().split("\nsnapshots:\n", 1)[1]
    return sorted(match.group(1) for match in re.finditer(r"^  (\S[^\n]*):(?: \{\})?$", text, re.M))


def verify_control(case, keys):
    if case == "cycle":
        expected = ["cycle-consumer@1.0.0(cycle-host@1.0.0)",
                    "cycle-host@1.0.0(cycle-plugin@1.0.0)",
                    "cycle-plugin@1.0.0(cycle-host@1.0.0)", "extra@1.0.0"]
        if keys != expected:
            raise RuntimeError("control failed: unexpected native pnpm cycle shape: " + repr(keys))
    elif case == "cycle-hashed":
        if "cycle-consumer@1.0.0(076b888d571dde1717a49649afd28f85)" not in keys:
            raise RuntimeError("control failed: unexpected native pnpm cycle hash")
    elif case == "provider":
        for peer in ("1.0.0", "2.0.0"):
            if f"provider-consumer@1.0.0(provider-peer@{peer})" not in keys:
                raise RuntimeError("control failed: native pnpm did not retain both provider contexts")


def registry_artifacts(port):
    packages = json.loads((ROOT / "fixture/packages.json").read_text())
    artifacts = {}
    for name, entries in packages.items():
        versions = {}
        for number, metadata in entries.items():
            manifest = {"name": name, "version": number, **metadata}
            buffer = io.BytesIO()
            with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
                body = json.dumps(manifest).encode()
                entry = tarfile.TarInfo("package/package.json")
                entry.size = len(body)
                archive.addfile(entry, io.BytesIO(body))
            tarball = buffer.getvalue()
            path = f"/{name}-{number}.tgz"
            artifacts[path] = tarball
            versions[number] = {**manifest, "dist": {
                "tarball": f"http://127.0.0.1:{port}{path}",
                "integrity": "sha512-" + base64.b64encode(hashlib.sha512(tarball).digest()).decode(),
                "shasum": hashlib.sha1(tarball).hexdigest()
            }}
        artifacts["/" + name] = json.dumps({"name": name, "versions": versions,
            "dist-tags": {"latest": max(entries)}}).encode()
    return artifacts


class Registry(BaseHTTPRequestHandler):
    def do_GET(self):
        data = self.server.artifacts.get(urlsplit(self.path).path)
        self.send_response(200 if data is not None else 404)
        self.end_headers()
        self.wfile.write(data if data is not None else b"{}")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, KeyError, IndexError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
