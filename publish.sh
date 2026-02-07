#!/bin/bash
set -e # Stops the script immediately if any command fails

# 0. START TIMER
START_TIME=$(date +%s)

# ==========================================
# 1. IMMEDIATE VERSION CHECK (FAIL FAST)
# ==========================================

echo "----------------------------------------------------"
echo "🔍 STEP 1: CHECKING GITHUB FOR EXISTING VERSIONS"
echo "----------------------------------------------------"

# Extract Version from pubspec.yaml
VERSION=$(grep 'version:' pubspec.yaml | cut -d ' ' -f 2 | cut -d '+' -f 1)
TAG="v$VERSION"

# Check if this tag already exists on GitHub
if git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
    echo "❌ CRITICAL ERROR: Version $TAG already exists on GitHub!"
    echo "👉 You must update the version in pubspec.yaml before releasing."
    echo "   Aborting process to prevent overwriting."
    exit 1
else
    echo "✅ Version $TAG is new. Proceeding..."
fi

# ==========================================
# 2. LOCAL CHECKS & TESTS
# ==========================================

echo "----------------------------------------------------"
echo "🔍 STEP 2: CHECKING FOR UNCOMMITTED CHANGES"
echo "----------------------------------------------------"
if [[ -n $(git status --porcelain) ]]; then
  echo "❌ Error: You have uncommitted changes."
  echo "👉 Please commit your changes in VS Code first."
  exit 1
fi

echo "----------------------------------------------------"
echo "🧪 STEP 3: RUNNING UNIT & WIDGET TESTS"
echo "----------------------------------------------------"
# Runs logic tests (Math, Serialization, Auth Mock)
flutter test

echo "✅ Unit Tests Passed!"

echo "----------------------------------------------------"
echo "🤖 STEP 4: RUNNING ROBOT (INTEGRATION) TESTS"
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
# 3. PREPARE RELEASE NOTES (AUTOMATED)
# ==========================================

echo "----------------------------------------------------"
echo "📝 STEP 5: GENERATING RELEASE NOTES"
echo "----------------------------------------------------"

# Try to find the previous tag
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [ -z "$PREV_TAG" ]; then
    # If no tags exist yet, use the very last commit message
    RELEASE_NOTES=$(git log -1 --pretty=%B)
else
    # Get all commit messages since the last tag
    RELEASE_NOTES=$(git log "$PREV_TAG"..HEAD --pretty='format:* %h - %s')
fi

echo "Captured Notes:"
echo "$RELEASE_NOTES"
# NO PROMPT HERE - Proceeding automatically

# ==========================================
# 4. BUILD
# ==========================================

echo "----------------------------------------------------"
echo "🛠  STEP 6: BUILDING APK"
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
# 5. RELEASE TO GITHUB
# ==========================================

echo "----------------------------------------------------"
echo "☁️  STEP 7: PUSHING TO GITHUB"
echo "----------------------------------------------------"
git push origin HEAD

echo "🏷  Creating tag $TAG..."
git tag "$TAG"
git push origin "$TAG"

echo "📦 Uploading APK to GitHub Releases..."
gh release create "$TAG" "$NEW_NAME" \
    --title "Version $VERSION" \
    --notes "$RELEASE_NOTES"

# ==========================================
# 6. FINISH & CALCULATE TIME
# ==========================================

END_TIME=$(date +%s)
TOTAL_SECONDS=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_SECONDS / 60))
SECONDS=$((TOTAL_SECONDS % 60))

echo "----------------------------------------------------"
echo "✅ SUCCESS! Version $TAG is now live on GitHub."
echo "⏱  Total Time: ${MINUTES}m ${SECONDS}s"
echo "----------------------------------------------------"