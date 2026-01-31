#!/bin/bash
set -e # <--- THIS STOPS THE SCRIPT INSTANTLY ON ANY ERROR

# 1. Check for uncommitted changes
if [[ -n $(git status --porcelain) ]]; then
  echo "❌ Error: You have uncommitted changes."
  echo "👉 Please write a commit message and click the ✔️ in VS Code first."
  exit 1
fi

# 2. Extract Version
VERSION=$(grep 'version:' pubspec.yaml | cut -d ' ' -f 2 | cut -d '+' -f 1)
TAG="v$VERSION"

echo "🚀 Starting Release Process for $TAG"

# 3. ASK FOR RELEASE NOTES
echo "📝 Enter the release notes (what's new?):"
read -p "> " RELEASE_NOTES

if [ -z "$RELEASE_NOTES" ]; then
  RELEASE_NOTES="Update for version $TAG"
fi

# 4. Push Code to GitHub
echo "☁️  Pushing code to GitHub..."
git push origin HEAD

# 5. Tag and Push Tag
echo "🏷  Tagging version $TAG..."
# Check if tag exists remotely to avoid crash
if git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
    echo "⚠️  Tag $TAG already exists on GitHub. Skipping tag push..."
else
    git tag "$TAG"
    git push origin "$TAG"
fi

# 6. Build APK
echo "🛠  Building Release APK... (Relax, this takes a minute)"
flutter build apk --release

# 7. Check if Build Succeeded
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK_PATH" ]; then
    echo "❌ Error: APK file not found at $APK_PATH"
    exit 1
fi

# 8. Rename and Upload
NEW_NAME="build/app/outputs/flutter-apk/Kaong_Monitor_$TAG.apk"
mv "$APK_PATH" "$NEW_NAME"

echo "📦 Uploading Release to GitHub..."
gh release create "$TAG" "$NEW_NAME" \
    --title "Version $VERSION" \
    --notes "$RELEASE_NOTES"

echo "✅ DONE! Version $TAG is live."