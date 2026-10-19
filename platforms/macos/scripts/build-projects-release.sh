#!/bin/bash
# Universal, ad-hoc signed fork build. No signing secrets or user settings needed.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="${1:-0.1.0}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected a numeric version, e.g. 0.1.0" >&2; exit 1; }
OUT="$ROOT/.build/projects-release"
APP="$OUT/PortKiller Projects.app"
if pgrep -f "$APP/Contents/MacOS/PortKiller" >/dev/null; then
    echo "Quit the public release app before rebuilding." >&2; exit 1
fi
mkdir -p "$OUT"
BACKUP=$(mktemp -d "${TMPDIR:-/tmp}/pk-release.XXXXXX")
RECORDER="$ROOT/.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Recorder.swift"
restore() {
    if [ -f "$BACKUP/Recorder.swift" ]; then cp "$BACKUP/Recorder.swift" "$RECORDER"; fi
    rm -rf "$BACKUP"
}
trap restore EXIT
swift package resolve
# Command Line Tools have no preview macro plugin. Full Xcode needs no workaround.
if ! xcrun --find actool >/dev/null 2>&1; then
    python3 - "$RECORDER" "$BACKUP/Recorder.swift" <<'PY'
from pathlib import Path
import re,sys
p,backup=map(Path,sys.argv[1:])
s=p.read_text(); patched=re.sub(r'^#Preview\s*\{.*?^\}', '', s, flags=re.M|re.S)
if patched!=s:
    backup.write_text(s);p.chmod(p.stat().st_mode|0o200);p.write_text(patched)
PY
fi
build_arch() {
    local arch="$1"
    local triple="$arch-apple-macosx15.0"
    local products
    local flags=(-c release --triple "$triple" -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=/build/port-killer" -Xswiftc -file-prefix-map -Xswiftc "$ROOT=/build/port-killer")
    swift build "${flags[@]}"
    products=$(swift build "${flags[@]}" --show-bin-path)
    python3 - "$products" "$ROOT" <<'PY'
from pathlib import Path
import sys
for p in Path(sys.argv[1]).glob('*.build/DerivedSources/resource_bundle_accessor.swift'):
    s=p.read_text()
    patched=s.replace('Bundle.main.bundleURL.appendingPathComponent','(Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent')
    patched=patched.replace(sys.argv[2],'/build/port-killer')
    if patched!=s:p.write_text(patched)
PY
    swift build "${flags[@]}"
    cp "$products/PortKiller" "$OUT/PortKiller-$arch"
    printf '%s' "$products" > "$OUT/products-$arch.txt"
}
build_arch arm64
build_arch x86_64
PRODUCTS=$(cat "$OUT/products-arm64.txt")
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ThirdPartyLicenses" "$APP/Contents/Frameworks"
lipo -create "$OUT/PortKiller-arm64" "$OUT/PortKiller-x86_64" -output "$APP/Contents/MacOS/PortKiller"
strip -S "$APP/Contents/MacOS/PortKiller"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp ../../LICENSE "$APP/Contents/Resources/LICENSE.txt"
for bundle in "$PRODUCTS"/*.bundle; do
    [ ! -d "$bundle" ] || ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
ditto "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
python3 - "$ROOT/.build/checkouts" "$APP/Contents/Resources/ThirdPartyLicenses" <<'PY_LICENSES'
from pathlib import Path
import shutil,sys
root,out=map(Path,sys.argv[1:])
included=set()
for package in root.iterdir():
    if not package.is_dir():continue
    for license in package.iterdir():
        if license.is_file() and license.name.lower().startswith(('license','notice','copying')):
            shutil.copyfile(license,out/(package.name+'-'+license.name))
            included.add(package.name)
assert {'KeyboardShortcuts','Defaults','LaunchAtLogin-Modern','Sparkle'} <= included
PY_LICENSES
install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/PortKiller"
python3 - "$APP/Contents/Info.plist" "$VERSION" "$(git rev-list --count HEAD)" <<'PY'
import plistlib,sys
p=sys.argv[1]
with open(p,'rb') as f:j=plistlib.load(f)
j.update(CFBundleIdentifier='com.gabritorres.portkiller.projects',CFBundleName='PortKiller Projects',CFBundleDisplayName='PortKiller Projects',CFBundleShortVersionString=sys.argv[2],CFBundleVersion=sys.argv[3],PKDisableUpdates=True,PKProjectDataFolder='PortKiller Projects',SUEnableAutomaticChecks=False,SUAllowsAutomaticUpdates=False)
j.update(PKRepositoryURL='https://github.com/gabritorres/port-killer',PKMaintainer='gabritorres · based on PortKiller by productdevbook')
for key in ['SUFeedURL','SUPublicEDKey','PKDevelopmentBuild']:j.pop(key,None)
with open(p,'wb') as f:plistlib.dump(j,f)
PY
# Local signature only: this beta is not Developer ID signed or Apple notarized.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
lipo "$APP/Contents/MacOS/PortKiller" -verify_arch arm64 x86_64
if strings "$APP/Contents/MacOS/PortKiller" | grep -F '/Users/' > "$OUT/private-path-check.txt"; then
    echo "Unexpected user path in release binary; inspect $OUT/private-path-check.txt" >&2; exit 1
fi
STAGE="$OUT/dmg-root"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/PortKiller Projects.app"
ln -s /Applications "$STAGE/Applications"
cp ../../INSTALL.md "$STAGE/INSTALL.txt"
ZIP="$OUT/PortKiller-Projects-$VERSION-macos-universal.zip"
DMG="$OUT/PortKiller-Projects-$VERSION-macos-universal.dmg"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
hdiutil create -volname 'PortKiller Projects' -srcfolder "$STAGE" -format UDZO -ov "$DMG"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > SHA256SUMS.txt)
echo "Release artifacts: $OUT"
