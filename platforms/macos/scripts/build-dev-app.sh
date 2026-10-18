#!/bin/bash
# Local debug app with separate preferences and no upstream update channel.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="PortKiller Projects Dev"
APP_DIR="$PWD/.build/development/$APP_NAME.app"
if pgrep -f "$APP_DIR/Contents/MacOS/PortKiller" >/dev/null; then
    echo "Quit $APP_NAME before rebuilding." >&2
    exit 1
fi

swift package resolve
PATCH_DIR=$(mktemp -d "${TMPDIR:-/tmp}/portkiller-dev.XXXXXX")
STAGING=""
RECORDER="$PWD/.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Recorder.swift"
restore_preview() {
    if [ -f "$PATCH_DIR/Recorder.swift" ]; then
        cp "$PATCH_DIR/Recorder.swift" "$RECORDER"
    fi
    rm -rf "$PATCH_DIR"
    if [ -n "$STAGING" ] && [ -d "$STAGING" ]; then
        rm -rf "$STAGING"
    fi
}
trap restore_preview EXIT

# Apple Command Line Tools include SwiftUI but not Xcode's preview macro plugin.
# Omit dependency previews only for this build, then restore the checkout.
if ! xcrun --find actool >/dev/null 2>&1; then
    python3 - "$RECORDER" "$PATCH_DIR/Recorder.swift" <<'PY'
from pathlib import Path
import re
import sys
source, backup = map(Path, sys.argv[1:])
original = source.read_text()
patched = re.sub(r'^#Preview\s*\{.*?^\}', '', original, flags=re.M | re.S)
if patched != original:
    backup.write_text(original)
    source.chmod(source.stat().st_mode | 0o200)
    source.write_text(patched)
PY
fi

swift build
PRODUCTS=$(swift build --show-bin-path)
# SwiftPM's generated accessors assume a command-line executable. Teach the
# ignored build products to find bundles in a standard macOS app layout.
python3 - "$PRODUCTS" <<'PY'
from pathlib import Path
import sys
for accessor in Path(sys.argv[1]).glob('*.build/DerivedSources/resource_bundle_accessor.swift'):
    original = accessor.read_text()
    patched = original.replace('Bundle.main.bundleURL.appendingPathComponent',
        '(Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent')
    if patched != original:
        accessor.write_text(patched)
PY
swift build
mkdir -p "$PWD/.build/development"
STAGING=$(mktemp -d "$PWD/.build/development/app.XXXXXX")
APP="$STAGING/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$PRODUCTS/PortKiller" "$APP/Contents/MacOS/PortKiller"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for bundle in "$PRODUCTS"/*.bundle; do
    [ -d "$bundle" ] || continue
    ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
ditto "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/PortKiller"
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib
import sys
path = sys.argv[1]
with open(path, 'rb') as handle:
    info = plistlib.load(handle)
info.update(CFBundleIdentifier='com.gabritorres.portkiller.projects.dev',
            CFBundleName='PortKiller Projects Dev',
            CFBundleDisplayName='PortKiller Projects Dev',
            PKDevelopmentBuild=True, SUEnableAutomaticChecks=False,
            SUAllowsAutomaticUpdates=False)
info.pop('SUFeedURL', None)
info.pop('SUPublicEDKey', None)
with open(path, 'wb') as handle:
    plistlib.dump(info, handle)
PY
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
rm -rf "$APP_DIR"
mv "$APP" "$APP_DIR"
rmdir "$STAGING"
echo "Local app: $APP_DIR"
echo "Open with: open \"$APP_DIR\""
