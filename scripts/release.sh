#!/bin/zsh
# Publishes a release: signed, notarized DMG, appcast for Sparkle, GitHub release, and the Homebrew cask. Usage: scripts/release.sh 0.1.0
# Needs, on the releasing Mac only: a Developer ID certificate, Sparkle's signing key in the keychain (made once by
# Sparkle's generate_keys, public half in scripts/sparkle-public-key.txt), `gh`, and ~/.config/itda-signing/env with
# NOTARY_KEY (path to an App Store Connect .p8), NOTARY_KEY_ID and NOTARY_ISSUER.
set -euo pipefail
cd "${0:A:h}/.."
version=$1
[[ -z "$(git status --porcelain)" ]] || { echo "Commit first: a release is one commit."; exit 1; }
source ~/.config/itda-signing/env
security find-identity -v -p codesigning | grep -q "Developer ID Application" || { echo "No Developer ID certificate."; exit 1; }

ITDA_VERSION=$version scripts/build-app.sh
out=build/release; rm -rf "$out"; mkdir -p "$out"
staging=$(mktemp -d); cp -R build/Itda.app "$staging/"; ln -s /Applications "$staging/Applications"
dmg="$out/Itda.dmg"
hdiutil create -quiet -volname Itda -srcfolder "$staging" -ov -format UDZO "$dmg"
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)
codesign --force --timestamp --sign "$identity" "$dmg"
xcrun notarytool submit "$dmg" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
xcrun stapler staple "$dmg"
spctl -a -t open --context context:primary-signature "$dmg"

bin=.build/artifacts/sparkle/Sparkle/bin
signature=$("$bin/sign_update" "$dmg")
sha=$(shasum -a 256 "$dmg" | cut -d' ' -f1)
cat > "$out/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Itda</title>
<item><title>$version</title><sparkle:version>$(git rev-list --count HEAD)</sparkle:version><sparkle:shortVersionString>$version</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion><pubDate>$(LC_ALL=C date -R)</pubDate>
<enclosure url="https://github.com/hrsong99/itda/releases/download/v$version/Itda.dmg" type="application/octet-stream" $signature/></item>
</channel></rss>
XML

# Everything that can fail goes first. Running it again after a failure past here replaces the assets and carries on.
tap=$(mktemp -d)
gh repo clone hrsong99/homebrew-itda "$tap" -- --quiet
mkdir -p "$tap/Casks"
sed -e "s/@VERSION@/$version/" -e "s/@SHA@/$sha/" scripts/itda.cask.rb > "$tap/Casks/itda.rb"
git -C "$tap" add -A
git -C "$tap" diff --cached --quiet || git -C "$tap" commit -qm "Itda $version"

# The tag has to name what was just built.
git push -q origin HEAD
if gh release view "v$version" >/dev/null 2>&1; then
  gh release upload "v$version" "$dmg" "$out/appcast.xml" --clobber
else
  gh release create "v$version" "$dmg" "$out/appcast.xml" --target "$(git rev-parse HEAD)" --title "Itda $version" --generate-notes
fi
git -C "$tap" push -q
echo "Released $version"
