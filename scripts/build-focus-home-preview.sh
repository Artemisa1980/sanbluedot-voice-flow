#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
package_dir="$project_root/macos"
# A single latest output directory keeps both the daily app and disk usage clean.
mkdir -p "$project_root/dist/previews"
rm -rf "$project_root/dist/previews"/focus-home.* 2>/dev/null || true
preview_root=$(mktemp -d "$project_root/dist/previews/focus-home.XXXXXX")
preview_app="$preview_root/Focus Home Preview.app"

swift build --package-path "$package_dir"
binary_dir="$package_dir/.build/out/Products/Debug"
[[ -f "$binary_dir/VoiceFlowMac" ]] || binary_dir=$(swift build --package-path "$package_dir" --show-bin-path)
mkdir -p "$preview_app/Contents/MacOS" "$preview_app/Contents/Resources/Fonts"
install -m 755 "$binary_dir/VoiceFlowMac" "$preview_app/Contents/MacOS/VoiceFlowMac"
install -m 644 "$package_dir/Resources/Info.plist" "$preview_app/Contents/Info.plist"
install -m 644 "$package_dir/Resources/Fonts/PressStart2P-Regular.ttf" "$preview_app/Contents/Resources/Fonts/"
install -m 644 "$package_dir/Resources/AppIcon.icns" "$preview_app/Contents/Resources/"
plutil -replace CFBundleIdentifier -string dot.sanblue.voiceflow.focus-home-preview "$preview_app/Contents/Info.plist"
plutil -replace CFBundleName -string 'Focus Home Preview' "$preview_app/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string 'Focus Home Preview' "$preview_app/Contents/Info.plist"
plutil -remove NSMicrophoneUsageDescription "$preview_app/Contents/Info.plist"
plutil -lint "$preview_app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$preview_app"
codesign --verify --deep --strict --verbose=2 "$preview_app"
echo "$preview_app"
