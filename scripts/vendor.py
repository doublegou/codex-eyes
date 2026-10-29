#!/usr/bin/env python3
"""Fetch pinned, integrity-checked native helpers. No npm/Node runtime is shipped."""
import base64
import hashlib
import io
import pathlib
import tarfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION = "0.3.1"
PACKAGES = {
    "arm64": ("arm64", "IoOJBJbg05Vi5CkOy40aWYKJRVs408UmugGKu26GB3MVWyrWlNQtZojDDUMoEHL13iXkmUGeu2jpCcPhTr80lQ=="),
    "x86_64": ("x64", "guPGDmd3Rg/KvaqZIyWVIHh08s5L343JRM5H3LvVoONw2nSrvhGkV4H1P1xdfRAlsnMZBLA5NHvdwq43L/k9Bw=="),
}
for architecture, (npm_arch, integrity) in PACKAGES.items():
    name = f"codex-auth-darwin-{npm_arch}"
    url = f"https://registry.npmjs.org/@loongphy/{name}/-/{name}-{VERSION}.tgz"
    archive = urllib.request.urlopen(url, timeout=60).read()
    actual = base64.b64encode(hashlib.sha512(archive).digest()).decode()
    if actual != integrity:
        raise RuntimeError(f"Integrity verification failed: {name}")
    destination = ROOT / "ThirdParty" / "bin" / architecture
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as package:
        for member, target in [("package/bin/codex-auth", destination / "codex-auth"),
                               ("package/LICENSE", ROOT / "ThirdParty" / "codex-auth.LICENSE")]:
            source = package.extractfile(member)
            if source is None:
                raise RuntimeError(f"Missing package member: {member}")
            target.write_bytes(source.read())
    (destination / "codex-auth").chmod(0o755)
    print(f"Verified codex-auth {VERSION} ({architecture})")
