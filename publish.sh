#!/bin/bash
set -e # Stops the script immediately if any command fails

# ==========================================
# 1. PRE-FLIGHT CHECKS & TESTS
# ==========================================

echo "----------------------------------------------------"
echo "🔍 STEP 1: CHECKING FOR UNCOMMITTED CHANGES"
echo "----------------------------------------------------"
if [[ -n $(git status --porcelain) ]]; then
  echo "❌ Error: You have uncommitted changes."
  echo "👉 Please commit your changes in VS Code first."
  exit 1
fi

echo "----------------------------------------------------"
echo "🧪 STEP 2: RUNNING UNIT & WIDGET TESTS"
echo "----------------------------------------------------"
# Runs logic tests (Math, Serialization, Auth Mock)
flutter test

echo "✅ Unit Tests Passed!"

echo "----------------------------------------------------"
echo "🤖 STEP 3: RUNNING INTEGRATION (ROBOT) TESTS"
echo "----------------------------------------------------"
# Checks if a phone is connected
if flutter devices | grep -q "0 connected"; then
  echo "⚠️  No device found! Cannot run Robot Tests."
  echo "❌ Aborting. Please connect a phone to verify the app works."
  exit 1
else
  # Runs the full app simulation
  flutter test integration_test/app_test.dart
  echo "✅ Robot Tests Passed!"
fi

# ==========================================
# 2. VERSIONING & NOTES
# ==========================================

# Extract Version from pubspec.yaml
VERSION=$(grep 'version:' pubspec.yaml | cut -d ' ' -f 2 | cut -d '+' -f 1)
TAG="v$VERSION"

echo "----------------------------------------------------"
echo "🚀 STEP 4: PREPARING RELEASE $TAG"
echo "----------------------------------------------------"

# --- AUTO-GENERATE RELEASE NOTES FROM COMMITS ---

# Try to find the previous tag
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [ -z "$PREV_TAG" ]; then
    # If no tags exist yet, use the very last commit message
    RELEASE_NOTES=$(git log -1 --pretty=%B)
else
    # If a tag exists, get all commit messages since that tag
    # Format: "* hash - message"
    RELEASE_NOTES=$(git log "$PREV_TAG"..HEAD --pretty='format:* %h - %s')
fi

echo "📝 Auto-generated Release Notes:"
echo "$RELEASE_NOTES"
echo "----------------------------------------------------"
echo "Press Enter to confirm these notes, or type new ones to overwrite:"
read -r USER_NOTES

if [ -n "$USER_NOTES" ]; then
  RELEASE_NOTES="$USER_NOTES"
fi

# ==========================================
# 3. BUILD
# ==========================================

echo "----------------------------------------------------"
echo "🛠  STEP 5: BUILDING APK"
echo "----------------------------------------------------"
flutter build apk --release --no-tree-shake-icons

# Verify APK exists
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK_PATH" ]; then
    echo "❌ Error: APK build failed or file not found."
    exit 1
fi

# Rename APK
NEW_NAME="build/app/outputs/flutter-apk/Pay_Tracker_$TAG.apk"
mv "$APK_PATH" "$NEW_NAME"

# ==========================================
# 4. RELEASE TO GITHUB
# ==========================================

echo "----------------------------------------------------"
echo "☁️  STEP 6: PUSHING TO GITHUB"
echo "----------------------------------------------------"
git push origin HEAD

# Tag handling
if git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
    echo "⚠️  Tag $TAG already exists. Skipping tag creation..."
else
    echo "🏷  Creating tag $TAG..."
    git tag "$TAG"
    git push origin "$TAG"
fi

echo "📦 Uploading APK to GitHub Releases..."
gh release create "$TAG" "$NEW_NAME" \
    --title "Version $VERSION" \
    --notes "$RELEASE_NOTES"

echo "----------------------------------------------------"
echo "✅ SUCCESS! Version $TAG is now live on GitHub."
echo "----------------------------------------------------"