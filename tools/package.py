"""Builds a local copy of the add-on zip: dist/Auctionator_VendorSniper-<version>.zip.

Releases are built by the GitHub workflow (.github/workflows/release.yml) when a version tag is pushed;
this script is for testing a zip by hand. The zip holds the add-on folder itself
(Auctionator_VendorSniper/...), with forward slashes in every path, which is what CurseForge and the WoW
add-on managers expect. Run from anywhere:

    python tools/package.py

The TOC's version is the placeholder @project-version@, which the release packager replaces with the
tag. Here it's replaced with `git describe --tags`: the latest tag, plus "-<commits>-g<hash>" when
there are commits after it.
"""
import pathlib
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = "Auctionator_VendorSniper"
SOURCE = ROOT / ADDON
INCLUDE = {".toc", ".lua", ".xml", ".tga", ".blp", ".png", ".ogg", ".mp3", ""}  # "" = LICENSE
PLACEHOLDER = "@project-version@"

try:
    version = subprocess.run(["git", "describe", "--tags"], cwd=ROOT, capture_output=True, text=True,
                             check=True).stdout.strip()
except (OSError, subprocess.CalledProcessError) as error:
    sys.exit(f"couldn't read the version from git tags: {error}")

dist = ROOT / "dist"
dist.mkdir(exist_ok=True)
target = dist / f"{ADDON}-{version}.zip"

files = sorted(p for p in SOURCE.rglob("*") if p.is_file() and p.suffix.lower() in INCLUDE)
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        name = f"{ADDON}/{path.relative_to(SOURCE).as_posix()}"
        if path.suffix.lower() == ".toc":
            archive.writestr(name, path.read_text(encoding="utf-8").replace(PLACEHOLDER, version))
        else:
            archive.write(path, name)

print(f"{target} ({len(files)} files)")
for path in files:
    print("  ", path.relative_to(SOURCE).as_posix())
