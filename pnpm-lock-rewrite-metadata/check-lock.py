import base64
import hashlib
from pathlib import Path
import re
import sys


def main():
    try:
        lock = Path(sys.argv[1]).read_text()
        archive = Path(sys.argv[2]).read_bytes()
    except OSError as error:
        print(f"cannot read fixture: {error}", file=sys.stderr)
        return 2
    integrity = "sha512-" + base64.b64encode(hashlib.sha512(archive).digest()).decode()
    settings = section(lock, "settings")
    packages = section(lock, "packages")
    snapshots = section(lock, "snapshots")
    package = entry(packages, "bundler@file:deps/bundler.tgz")
    snapshot = entry(snapshots, "bundler@file:deps/bundler.tgz")
    checks = {
        "settings.peersSuffixMaxLength: 80": "  peersSuffixMaxLength: 80\n" in settings,
        "local tarball version: 1.0.0": "    version: 1.0.0\n" in package,
        "local tarball integrity matches archive SHA-512": f"integrity: {integrity}" in package,
        "package bundledDependencies: [is-number]": "    bundledDependencies:\n      - is-number\n" in package,
        "bundled child has no separate registry entry or snapshot edge": (
            "  is-number@7.0.0:" not in packages
            and snapshot.strip() == "bundler@file:deps/bundler.tgz: {}"
        ),
    }
    for label, passed in checks.items():
        print(f"{'ok' if passed else 'MISSING/CHANGED'}: {label}")
    return 0 if all(checks.values()) else 1


def section(lock, name):
    match = re.search(rf"^{re.escape(name)}:\n(.*?)(?=^\S|\Z)", lock, re.M | re.S)
    return match.group(1) if match else ""


def entry(section_text, key):
    match = re.search(rf"^  {re.escape(key)}:.*?(?=^  \S|\Z)", section_text, re.M | re.S)
    return match.group(0) if match else ""


if __name__ == "__main__":
    sys.exit(main())
