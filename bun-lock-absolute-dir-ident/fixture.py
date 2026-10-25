import io
import json
import pathlib
import sys
import tarfile

root = pathlib.Path(sys.argv[1])
assets = root / "assets"
assets.mkdir(parents=True)
(assets / "child").mkdir()
for path in pathlib.Path("fixture/child").iterdir():
    (assets / "child" / path.name).write_bytes(path.read_bytes())
manifest = dict(name="host", version="1.0.0", main="index.js",
                dependencies={"child": "file:" + str(assets / "child")})
with tarfile.open(assets / "host.tgz", "w:gz") as archive:
    for name, data in {
        "package.json": json.dumps(manifest).encode(),
        "index.js": pathlib.Path("fixture/host/index.js").read_bytes(),
    }.items():
        info = tarfile.TarInfo("package/" + name)
        info.size = len(data)
        archive.addfile(info, io.BytesIO(data))
(root / "package.json").write_text(json.dumps(dict(
    name="root", private=True, dependencies={"host": "file:assets/host.tgz"})))
(root / ".npmrc").write_text("block-exotic-subdeps=false\nnode-linker=hoisted\n")
