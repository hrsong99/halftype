#!/bin/zsh
# Builds Itda.app from `swift build`: bundle, embedded framework, Info.plist, stable signature.
# A stable identity keeps Accessibility grants across rebuilds. With none on this Mac it signs ad hoc, and each build
# then needs granting again. Output: build/Itda.app
# Sharing a build: Gatekeeper blocks an Apple Development signature on other Macs. It needs a "Developer ID Application"
# certificate (the account holder makes one), then `codesign --options runtime --timestamp`, `xcrun notarytool submit --wait`
# and `xcrun stapler staple`. This script already prefers that identity once it exists; the last three steps aren't here yet.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --disable-keychain --product Itda
bin=$(swift build -c release --disable-keychain --show-bin-path)
app=build/Itda.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp "$bin/Itda" "$app/Contents/MacOS/Itda"
for framework in "$bin"/*.framework(N); do cp -R "$framework" "$app/Contents/Frameworks/"; done
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/Itda" 2>/dev/null || true

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.itda.Itda</string>
  <key>CFBundleName</key><string>Itda</string>
  <key>CFBundleExecutable</key><string>Itda</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)
[[ -n "$identity" ]] || identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)
[[ -n "$identity" ]] || identity=-
for framework in "$app/Contents/Frameworks"/*.framework(N); do codesign --force --sign "$identity" "$framework"; done
codesign --force --sign "$identity" --identifier app.itda.Itda "$app"
codesign --verify --deep --strict "$app"
echo "$PWD/$app signed by: $identity"
