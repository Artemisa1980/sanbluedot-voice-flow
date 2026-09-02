#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
package_dir="$project_root/macos"
app_dir="$project_root/dist/sanblueᵈᵒᵗ VoiceFlow.app"
staging_root=$(mktemp -d "${TMPDIR:-/tmp}/voiceflow-build.XXXXXX")
staged_app="$staging_root/${app_dir:t}"
trap 'rm -rf "$staging_root"' EXIT

swift build --package-path "$package_dir" -c release
binary_dir=$(swift build --package-path "$package_dir" -c release --show-bin-path)

mkdir -p "$staged_app/Contents/MacOS"
mkdir -p "$staged_app/Contents/Resources/python/src"
install -m 755 "$binary_dir/VoiceFlowMac" "$staged_app/Contents/MacOS/VoiceFlowMac"
install -m 644 "$package_dir/Resources/Info.plist" "$staged_app/Contents/Info.plist"
if [[ -f "$package_dir/Resources/AppIcon.icns" ]]; then
    install -m 644 "$package_dir/Resources/AppIcon.icns" "$staged_app/Contents/Resources/AppIcon.icns"
fi
if [[ -f "$package_dir/Resources/voiceflow-badge-round.png" ]]; then
    install -m 644 "$package_dir/Resources/voiceflow-badge-round.png" "$staged_app/Contents/Resources/voiceflow-badge-round.png"
fi
if [[ -d "$package_dir/Resources/Fonts" ]]; then
    mkdir -p "$staged_app/Contents/Resources/Fonts"
    cp -R "$package_dir/Resources/Fonts/"* "$staged_app/Contents/Resources/Fonts/"
fi
/usr/bin/rsync -a \
    --exclude='__pycache__' \
    --exclude='*.py[co]' \
    "$project_root/src/" "$staged_app/Contents/Resources/python/src/"
plutil -lint "$staged_app/Contents/Info.plist"

signing_identity=${VOICEFLOW_CODESIGN_IDENTITY:-}
if [[ -z "$signing_identity" ]]; then
    signing_identity=$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)
fi

if [[ -z "$signing_identity" ]]; then
    echo "No Apple Development signing identity is available." >&2
    echo "Set VOICEFLOW_CODESIGN_IDENTITY before building." >&2
    exit 1
fi

codesign --force --deep --options runtime --timestamp=none \
    --entitlements "$package_dir/Resources/VoiceFlowMac.entitlements" \
    --sign "$signing_identity" "$staged_app"

# Verification is part of the build contract, not a manual afterthought. Building in a
# fresh staging directory also prevents stale or unsigned resources from surviving an
# earlier build.
codesign --verify --deep --strict --verbose=2 "$staged_app"

mkdir -p "${app_dir:h}"
rm -rf "$app_dir"
mv "$staged_app" "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"

echo "$app_dir"
