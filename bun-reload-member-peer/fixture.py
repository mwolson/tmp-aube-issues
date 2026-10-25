import io
import json
from pathlib import Path
import sys
import tarfile

root = Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=True)

def write(name, value):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")

def pack(filename, manifest, script):
    with tarfile.open(root / filename, "w:gz") as archive:
        for name, body in [("package.json", json.dumps(manifest)), ("index.js", script)]:
            data = body.encode()
            info = tarfile.TarInfo("package/" + name)
            info.size, info.mode = len(data), 0o644
            archive.addfile(info, io.BytesIO(data))

pack("react18.tgz", {"name": "react", "version": "18.0.0"}, "module.exports = '18.0.0';\n")
pack("react19.tgz", {"name": "react", "version": "19.0.0"}, "module.exports = '19.0.0';\n")
pack("consumer.tgz", {"name": "consumer", "version": "1.0.0", "peerDependencies": {"react": "^19.0.0"}}, "module.exports = require('react');\n")
write("package.json", {"name": "root", "private": True, "workspaces": ["apps/*"], "dependencies": {"react": "file:react18.tgz"}})
write("apps/app/package.json", {"name": "app", "dependencies": {"consumer": "file:../../consumer.tgz", "react": "file:../../react19.tgz"}})
