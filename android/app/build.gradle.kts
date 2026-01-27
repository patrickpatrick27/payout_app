name: Build and Release APK

on:
  push:
    tags:
      - "v*" # Triggers when you push a tag like v1.0.0

permissions:
  contents: write # REQUIRED for creating releases

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      # 1. Setup Java
      - uses: actions/setup-java@v3
        with:
          distribution: 'zulu'
          java-version: '17'

      # 2. Setup Flutter
      - uses: subosito/flutter-action@v2
        with:
          channel: 'stable'

      # 3. Restore the Keystore (The Magic Step)
      - name: Decode Keystore
        run: |
          echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 --decode > android/app/upload-keystore.jks

      # 4. Create key.properties (So Gradle can find the password)
      - name: Create key.properties
        run: |
          echo "storePassword=${{ secrets.ANDROID_STORE_PASSWORD }}" > android/key.properties
          echo "keyPassword=${{ secrets.ANDROID_KEY_PASSWORD }}" >> android/key.properties
          echo "keyAlias=upload" >> android/key.properties
          echo "storeFile=upload-keystore.jks" >> android/key.properties

      # 5. Install Dependencies
      - name: Get Dependencies
        run: flutter pub get

      # 6. Build APK
      - name: Build APK
        run: flutter build apk --release --no-tree-shake-icons

      # 7. Create GitHub Release & Attach APK
      - name: Release to GitHub
        uses: softprops/action-gh-release@v1
        if: startsWith(github.ref, 'refs/tags/')
        with:
          files: build/app/outputs/flutter-apk/app-release.apk