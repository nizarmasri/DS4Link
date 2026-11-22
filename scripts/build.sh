#!/bin/zsh
# Build DS4Link.app as a universal (Apple silicon + Intel) binary, sign it, install it to
# ~/Applications and produce build/DS4Link.zip for other Macs.
#
#   scripts/build.sh            build, sign, install
#   SIGN_IDENTITY="-" ...       force ad-hoc signing
#   DEST=/Applications/DS4Link.app scripts/build.sh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

APP="$ROOT/build/DS4Link.app"
DEST="${DEST:-$HOME/Applications/DS4Link.app}"
# Signing: SIGN_IDENTITY, else the identity in scripts/.signing-identity (not committed), else
# ad hoc, which runs fine on any Mac. A stable identity keeps permissions across rebuilds.
if [[ -z "${SIGN_IDENTITY:-}" && -f "$ROOT/scripts/.signing-identity" ]]; then
  SIGN_IDENTITY="$(<"$ROOT/scripts/.signing-identity")"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# SwiftPM puts both architectures at the same output path, so each one is copied aside
# before the next build overwrites it.
SLICES="$ROOT/build/slices"
rm -rf "$SLICES"
mkdir -p "$SLICES"
for arch in arm64 x86_64; do
  swift build -c release --arch "$arch"
  cp "$(swift build -c release --arch "$arch" --show-bin-path)/DS4Link" "$SLICES/DS4Link-$arch"
  lipo "$SLICES/DS4Link-$arch" -verify_arch "$arch"
done
ARM="$SLICES/DS4Link-arm64"
INTEL="$SLICES/DS4Link-x86_64"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM" "$INTEL" -output "$APP/Contents/MacOS/DS4Link"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# The icon is drawn by the app itself; regenerate it whenever it is missing.
ICNS="$ROOT/Resources/AppIcon.icns"
if [[ ! -f "$ICNS" ]]; then
  WORK="$(mktemp -d)"
  "$ARM" --render-icon "$WORK/icon.png" >/dev/null
  mkdir "$WORK/AppIcon.iconset"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$WORK/AppIcon.iconset" -o "$ICNS"
  rm -rf "$WORK"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"

# Quit a running copy so the installed app can be replaced.
osascript -e 'tell application id "com.nizar.ds4link" to quit' >/dev/null 2>&1 || true
mkdir -p "${DEST:h}"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

# Same package the in-app "Send to Another Mac" button makes.
STAGE="$(mktemp -d)"
mkdir "$STAGE/DS4Link"
cp -R "$APP" "$STAGE/DS4Link/DS4Link.app"
"$ARM" --install-notes > "$STAGE/DS4Link/How to install.txt"
rm -f "$ROOT/build/DS4Link.zip"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/DS4Link" "$ROOT/build/DS4Link.zip"
rm -rf "$STAGE"

echo "Signed with: $SIGN_IDENTITY"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/DS4Link")"
echo "Installed:     $DEST"
echo "For other Macs: $ROOT/build/DS4Link.zip"
