#!/bin/sh
set -e

echo "Installing XcodeGen..."
brew install xcodegen

echo "Generating Xcode project..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

# Use build setting variables so Xcode Cloud / Fastlane control version numbers
echo "Fixing Info.plist version variables..."
for plist in GT3Companion/Info.plist GT3CompanionMac/Info.plist GT3CompanionWatch/Info.plist GT3CompanionWidgets/Info.plist GT3CompanionVision/Info.plist; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion \$(CURRENT_PROJECT_VERSION)" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString \$(MARKETING_VERSION)" "$plist"
done

echo "Xcode project generated successfully."
