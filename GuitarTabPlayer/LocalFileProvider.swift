name: iOS

# Compiles the app on a macOS runner — the only place an iOS app can be built.
# `test` proves it compiles and the domain tests pass.
# `ipa` produces an installable artifact; see INSTALL.md for the signing options.

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  SCHEME: GuitarTabPlayer
  PROJECT: GuitarTabPlayer.xcodeproj

jobs:
  test:
    name: Build & test (simulator)
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 16
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Show toolchain
        run: xcodebuild -version && swift --version

      - name: Build for simulator
        run: |
          set -o pipefail
          xcodebuild build-for-testing \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
            -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO

      - name: Run unit tests
        run: |
          set -o pipefail
          xcodebuild test-without-building \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
            -derivedDataPath build \
            -resultBundlePath TestResults.xcresult \
            CODE_SIGNING_ALLOWED=NO

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: TestResults.xcresult

  ipa:
    name: Unsigned .ipa
    runs-on: macos-15
    needs: test
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 16
        run: sudo xcode-select -s /Applications/Xcode_16.app

      # Builds a device binary without touching a signing identity. The result is a real .ipa
      # but it is NOT signed: it cannot be installed as-is. Re-sign it with your own certificate
      # (see INSTALL.md), or swap this job for one that uses your secrets and `-exportArchive`.
      - name: Archive without signing
        run: |
          set -o pipefail
          xcodebuild archive \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -configuration Release \
            -destination 'generic/platform=iOS' \
            -archivePath build/GuitarTabPlayer.xcarchive \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGN_IDENTITY="" \
            AD_HOC_CODE_SIGNING_ALLOWED=YES

      - name: Package as .ipa
        run: |
          mkdir -p build/Payload
          cp -R build/GuitarTabPlayer.xcarchive/Products/Applications/GuitarTabPlayer.app build/Payload/
          (cd build && zip -qry GuitarTabPlayer-unsigned.ipa Payload)
          ls -lh build/GuitarTabPlayer-unsigned.ipa

      - name: Upload .ipa
        uses: actions/upload-artifact@v4
        with:
          name: GuitarTabPlayer-unsigned-ipa
          path: build/GuitarTabPlayer-unsigned.ipa
          retention-days: 30
