#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
architecture="${1:-$(uname -m)}"
mode="${2:-package}"
case "$architecture" in arm64|x86_64|universal) ;; *) echo "Usage: package.sh [arm64|x86_64|universal] [--release]" >&2; exit 1 ;; esac
case "$mode" in package|--release) ;; *) echo "Unknown package mode: $mode" >&2; exit 1 ;; esac
identity="${CODEX_EYES_SIGN_IDENTITY:--}"
if [[ "$mode" == "--release" ]]; then
    if [[ "$identity" != "Developer ID Application:"* || -z "${CODEX_EYES_NOTARY_PROFILE:-}" ]]; then
        echo "Notarized packaging needs CODEX_EYES_SIGN_IDENTITY='Developer ID Application: …' and CODEX_EYES_NOTARY_PROFILE." >&2
        echo "Run without --release to package with the configured signing identity." >&2
        exit 1
    fi
fi
python3 scripts/vendor.py
if [[ "$architecture" == "universal" ]]; then
    swift build -c release --arch arm64 --arch x86_64 --disable-sandbox
    binary_dir="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path --disable-sandbox)"
else
    swift build -c release --arch "$architecture" --disable-sandbox
    binary_dir="$(swift build -c release --arch "$architecture" --show-bin-path --disable-sandbox)"
fi
mkdir -p dist
stage="$(mktemp -d dist/.codexeyes-stage.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
app="$stage/Codex Eyes.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources/Licenses"
cp "$binary_dir/CodexEyes" "$app/Contents/MacOS/CodexEyes"
cp "$binary_dir/CodexEyesHook" "$app/Contents/Helpers/CodexEyesHook"
if [[ "$architecture" == "universal" ]]; then
    lipo -create ThirdParty/bin/arm64/codex-auth ThirdParty/bin/x86_64/codex-auth -output "$app/Contents/Helpers/codex-auth"
else
    cp "ThirdParty/bin/$architecture/codex-auth" "$app/Contents/Helpers/codex-auth"
fi
cp LICENSE ThirdParty/NOTICE.md ThirdParty/codex-auth.LICENSE "$app/Contents/Resources/Licenses/"
cp Assets/NOTICE.md "$app/Contents/Resources/Licenses/AppIcon-NOTICE.md"
cp docs/compatibility.md "$app/Contents/Resources/"
cp -R "$binary_dir/CodexEyes_CodexEyesCore.bundle" "$app/Contents/Resources/"
swift scripts/icon.swift dist/AppIcon.iconset
iconutil -c icns dist/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexEyes</string>
<key>CFBundleIdentifier</key><string>app.codexeyes.mac</string>
<key>CFBundleName</key><string>Codex Eyes</string>
<key>CFBundleDisplayName</key><string>Codex Eyes</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
for executable in "$app/Contents/Helpers/codex-auth" "$app/Contents/Helpers/CodexEyesHook"; do
    if [[ "$identity" == "-" ]]; then
        codesign --force --sign - "$executable"
    else
        codesign --force --options runtime --timestamp --sign "$identity" "$executable"
    fi
done
if [[ "$identity" == "-" ]]; then
    codesign --force --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --deep --strict "$app"
python3 scripts/test-account-import.py "$app/Contents/Helpers/codex-auth"
artifact="dist/CodexEyes-1.0.0-$architecture"
if [[ "$mode" == "--release" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/notarization.zip"
    xcrun notarytool submit "$stage/notarization.zip" --keychain-profile "$CODEX_EYES_NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose "$app"
fi
bash scripts/dmg.sh "$app" "$artifact.dmg"
if [[ "$identity" != "-" ]]; then
    codesign --force --timestamp --sign "$identity" "$artifact.dmg"
fi
if [[ "$mode" == "--release" ]]; then
    xcrun notarytool submit "$artifact.dmg" --keychain-profile "$CODEX_EYES_NOTARY_PROFILE" --wait
    xcrun stapler staple "$artifact.dmg"
    xcrun stapler validate "$artifact.dmg"
    spctl --assess --type open --context context:primary-signature --verbose "$artifact.dmg"
fi
ditto -c -k --sequesterRsrc --keepParent "$app" "$artifact.zip"
(cd dist && shasum -a 256 "$(basename "$artifact").dmg" "$(basename "$artifact").zip") > "$artifact.sha256"
if [[ -d "dist/Codex Eyes.app" ]]; then
    mv "dist/Codex Eyes.app" "$stage/previous.app"
fi
mv "$app" "dist/Codex Eyes.app"
echo "Built dist/Codex Eyes.app ($architecture). Signing identity: $identity"
echo "Installer: $artifact.dmg"
if [[ "$mode" != "--release" ]]; then
    echo "Apple notarization was not requested. See docs/releasing.md for signing options."
fi
