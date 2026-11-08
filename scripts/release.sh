#!/bin/zsh
# Publishes a release: signed, notarized DMG, appcast for Sparkle, GitHub release, and the Homebrew cask. Usage: scripts/release.sh 0.1.0
# Needs, on the releasing Mac only: `gh`, a Developer ID certificate in a keychain called halftype-signing, and
# ~/.config/halftype-signing/env with KEYCHAIN_PASSWORD, NOTARY_KEY (path to an App Store Connect .p8), NOTARY_KEY_ID, NOTARY_ISSUER
# and SPARKLE_KEY (a file from Sparkle's generate_keys -x, public half in scripts/sparkle-public-key.txt).
set -euo pipefail
cd "${0:A:h}/.."
version=$1
[[ -z "$(git status --porcelain)" ]] || { echo "Commit first: a release is one commit."; exit 1; }
source ~/.config/halftype-signing/env
security unlock-keychain -p "$KEYCHAIN_PASSWORD" halftype-signing.keychain
security find-identity -v -p codesigning | grep -q "Developer ID Application" || { echo "No Developer ID certificate."; exit 1; }

HALFTYPE_VERSION=$version scripts/build-app.sh
out=build/release; rm -rf "$out"; mkdir -p "$out"
staging=$(mktemp -d); cp -R build/Halftype.app "$staging/"; ln -s /Applications "$staging/Applications"
dmg=build/Halftype.dmg  # outside $out, so generate_appcast sees only the update copy
hdiutil create -quiet -volname Halftype -srcfolder "$staging" -ov -fs APFS -format ULFO "$dmg"
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)
codesign --force --timestamp --sign "$identity" "$dmg"
xcrun notarytool submit "$dmg" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
xcrun stapler staple "$dmg"
spctl -a -t open --context context:primary-signature "$dmg"

bin=.build/artifacts/sparkle/Sparkle/bin
sha=$(shasum -a 256 "$dmg" | cut -d' ' -f1)
# The same DMG under a second name for Sparkle, so GitHub's counts tell new installs from updates (scripts/usage.sh).
cp "$dmg" "$out/Halftype-update.dmg"
"$bin/generate_appcast" --ed-key-file "$SPARKLE_KEY" --download-url-prefix "https://github.com/hrsong99/halftype/releases/download/v$version/" "$out"

# Everything that can fail goes first. Running it again after a failure past here replaces the assets and carries on.
tap=$(mktemp -d)
gh repo clone hrsong99/homebrew-halftype "$tap" -- --quiet
mkdir -p "$tap/Casks"
sed -e "s/@VERSION@/$version/" -e "s/@SHA@/$sha/" scripts/halftype.cask.rb > "$tap/Casks/halftype.rb"
git -C "$tap" add -A
git -C "$tap" diff --cached --quiet || git -C "$tap" commit -qm "Halftype $version"

# The tag has to name what was just built.
git push -q origin HEAD
if gh release view "v$version" >/dev/null 2>&1; then
  gh release upload "v$version" "$dmg" "$out/Halftype-update.dmg" "$out/appcast.xml" --clobber
else
  gh release create "v$version" "$dmg" "$out/Halftype-update.dmg" "$out/appcast.xml" --target "$(git rev-parse HEAD)" --title "Halftype $version" --generate-notes
fi
git -C "$tap" push -q
echo "Released $version"
