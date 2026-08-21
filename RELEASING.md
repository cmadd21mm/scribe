# Releasing Scribe

Public releases are built locally because Developer ID and Sparkle signing keys
remain in the maintainer's Mac Keychain. GitHub Actions independently tests the
tag and produces an unsigned development artifact; that artifact must never be
published as the user-facing download.

## 1. Prepare the source

1. Start from a clean, up-to-date `main` branch.
2. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `Sources/Scribe/Info.plist`.
3. Add the release notes to `CHANGELOG.md`.
4. Run the policy check and complete test suite:

   ```sh
   sh scripts/check-no-runtime-network.sh
   swift test
   ```

## 2. Build and notarize

Set the Developer ID identity and the saved `notarytool` Keychain profile for
the current Mac, then build the universal installer:

```sh
APPLE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_NOTARY_PROFILE="scribe-notary" \
sh scripts/package-dmg.sh
```

The command waits for Apple notarization and staples the accepted ticket to
`dist/Scribe.dmg`. Stop if notarization is not accepted.

## 3. Validate the installer

```sh
codesign --verify --deep --strict --all-architectures --verbose=4 dist/Scribe.app
spctl --assess --type execute --verbose=4 dist/Scribe.app
xcrun stapler validate dist/Scribe.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 dist/Scribe.dmg
hdiutil verify dist/Scribe.dmg
lipo -archs dist/Scribe.app/Contents/MacOS/Scribe
```

Gatekeeper must report `Notarized Developer ID`, and `lipo` must report both
`arm64` and `x86_64`.

## 4. Sign the update feed

Generate the Sparkle appcast with the private update key stored in the Keychain:

```sh
sh scripts/make-appcast.sh dist/Scribe.dmg
```

Confirm that `dist/appcast.xml` contains the intended marketing version, build
number, minimum macOS version, versioned GitHub download URL, exact DMG length,
and an `edSignature`.

## 5. Publish through a draft

Replace `VERSION` with the marketing version, copy the installer to its public
asset name, and create a draft release targeting the exact merged `main` commit:

```sh
cp dist/Scribe.dmg dist/Scribe-VERSION.dmg
gh release create vVERSION \
  dist/Scribe-VERSION.dmg dist/appcast.xml \
  --target MAIN_COMMIT_SHA \
  --title "Scribe VERSION" \
  --generate-notes \
  --draft
```

Compare GitHub's uploaded SHA-256 digests and file sizes with the local files.
Publish only after they match:

```sh
gh release edit vVERSION --draft=false --latest
```

## 6. Verify the public path

Download both assets back from the published release. Confirm their SHA-256
hashes match, validate the downloaded DMG with Gatekeeper and `stapler`, and
confirm this URL returns the new appcast:

```text
https://github.com/cmadd21mm/scribe/releases/latest/download/appcast.xml
```

Finally, wait for the tag-triggered `release` workflow to pass. Test the
in-app **Check for Updates…** flow from the previous public version.
