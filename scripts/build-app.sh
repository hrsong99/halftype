#!/bin/zsh
# Builds Halftype.app from `swift build`: bundle, embedded framework, Info.plist, stable signature.
# A stable identity keeps Accessibility grants across rebuilds. With none on this Mac it signs ad hoc, and each build
# then needs granting again. Output: build/Halftype.app
# The app was called Itda: the executable, bundle ID and Application Support folder keep that name, so Accessibility
# grants, settings, downloaded models and Sparkle updates carry over.
# Set ITDA_VERSION for a release, which gets the update feed. Without it the build is a local one, and never updates itself.
# Signs with a Developer ID if this Mac has one, with hardened runtime and a timestamp, as notarizing needs. See scripts/release.sh.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --disable-keychain --product Itda
bin=$(swift build -c release --disable-keychain --show-bin-path)
app=build/Halftype.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp "$bin/Itda" "$app/Contents/MacOS/Itda"
for framework in "$bin"/*.framework(N); do cp -R "$framework" "$app/Contents/Frameworks/"; done
# The window's sky shader. Bundle.module looks in Contents/Resources first, and stops the app if it isn't there.
cp -R "$bin/Itda_ItdaApp.bundle" "$app/Contents/Resources/"
cp LICENSE scripts/llama.cpp-LICENSE Resources/AppIcon.icns Resources/MenuBarTemplate*.png "$app/Contents/Resources/"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE"
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/Itda" 2>/dev/null || true

version=${ITDA_VERSION:-0.0.0}
build=$(git rev-list --count HEAD)
feed=""
if [[ -n "${ITDA_VERSION:-}" ]]; then
  feed="<key>SUFeedURL</key><string>https://github.com/hrsong99/itda/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$(cat scripts/sparkle-public-key.txt)</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAutomaticallyUpdate</key><true/>"
fi
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.itda.Itda</string>
  <key>CFBundleName</key><string>Halftype</string>
  <key>CFBundleDisplayName</key><string>Halftype</string>
  <key>CFBundleExecutable</key><string>Itda</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  $feed
</dict></plist>
PLIST

# A keychain of its own, as CI does, so signing never waits on a dialog nobody may be there to answer.
if [[ -f ~/.config/itda-signing/env ]]; then
  source ~/.config/itda-signing/env
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" itda-signing.keychain
fi
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)
flags=(--force --options runtime --timestamp)
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)
  [[ -n "$identity" ]] || identity=-
  flags=(--force)
fi
# Inside out, as a signature covers what it contains. Sparkle ships helpers inside its framework.
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
if [[ -d "$sparkle" ]]; then
  for helper in "$sparkle"/XPCServices/*.xpc(N) "$sparkle/Autoupdate" "$sparkle/Updater.app"; do codesign "${flags[@]}" --sign "$identity" "$helper"; done
fi
for framework in "$app/Contents/Frameworks"/*.framework(N); do codesign "${flags[@]}" --sign "$identity" "$framework"; done
codesign "${flags[@]}" --sign "$identity" --identifier app.itda.Itda "$app"
codesign --verify --deep --strict "$app"
echo "$PWD/$app signed by: $identity"
