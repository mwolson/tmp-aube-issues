import io
import json
from pathlib import Path
import sys
import tarfile

root = Path(sys.argv[1]).resolve()
kind = sys.argv[2]

def write(name, value):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n" if isinstance(value, dict) else value)

leaf = {"name": "leaf", "version": "1.0.0"}
if kind == "directory":
    write("vendor/leaf/package.json", leaf)
    write("vendor/leaf/index.js", "module.exports = 'leaf ok';\n")
    leaf_path = root / "vendor/leaf"
else:
    leaf_path = root / "leaf.tgz"
    with tarfile.open(leaf_path, "w:gz") as archive:
        for name, body in [("package.json", json.dumps(leaf)), ("index.js", "module.exports = 'leaf ok';\n")]:
            data = body.encode()
            info = tarfile.TarInfo("package/" + name)
            info.size, info.mode = len(data), 0o644
            archive.addfile(info, io.BytesIO(data))
write("vendor/host/package.json", {
    "name": "host", "version": "1.0.0", "dependencies": {"leaf": "file:" + str(leaf_path)}
})
write("vendor/host/index.js", "module.exports = require('leaf');\n")
write("package.json", {"name": "root", "private": True, "workspaces": ["apps/*"]})
write("apps/app/package.json", {"name": "app", "dependencies": {"host": "file:../../vendor/host"}})
