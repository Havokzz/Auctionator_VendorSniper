"""Builds the CurseForge upload: dist/Auctionator_VendorSniper-<version>.zip.

The zip holds the add-on folder itself (Auctionator_VendorSniper/...), with forward slashes in every
path, which is what CurseForge and the WoW add-on managers expect. Run from anywhere:

    python tools/package.py
"""
import pathlib
import re
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = "Auctionator_VendorSniper"
SOURCE = ROOT / ADDON
INCLUDE = {".toc", ".lua", ".xml", ".tga", ".blp", ".png", ".ogg", ".mp3", ""}  # "" = LICENSE

toc = (SOURCE / f"{ADDON}.toc").read_text(encoding="utf-8")
match = re.search(r"^## Version:\s*(\S+)", toc, re.M)
if not match:
    sys.exit("no ## Version line in the TOC")
version = match.group(1)

dist = ROOT / "dist"
dist.mkdir(exist_ok=True)
target = dist / f"{ADDON}-{version}.zip"

files = sorted(p for p in SOURCE.rglob("*") if p.is_file() and p.suffix.lower() in INCLUDE)
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        archive.write(path, f"{ADDON}/{path.relative_to(SOURCE).as_posix()}")

print(f"{target} ({len(files)} files)")
for path in files:
    print("  ", path.relative_to(SOURCE).as_posix())
