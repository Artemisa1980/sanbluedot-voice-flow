#!/bin/zsh
# Build and install the daily app.
#
# This used to assemble the bundle by hand from a SwiftPM build. It still could, and the
# result still ran — but it could not produce App Intents metadata, because that is an
# Xcode build phase, so an app installed from here was one Siri, Spotlight and Shortcuts
# could not see. Two ways to build one app, one of them quietly lesser, is a trap nobody
# should have to remember. There is one way now, and this is still the command for it.
#
# The Xcode project compiles the same sources, links `VoiceFlowMacCore` as the package's
# library product, embeds the Python engine and the Apple cleanup helper, signs with the
# same Apple Development identity, and verifies the signature before this script copies
# anything into `dist/`.
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
project="$project_root/macos/VoiceFlow.xcodeproj"
app_dir="$project_root/dist/sanblueᵈᵒᵗ VoiceFlow.app"
derived=$(mktemp -d "${TMPDIR:-/tmp}/voiceflow-build.XXXXXX")
trap 'rm -rf "$derived"' EXIT

if [[ ! -d "$project" ]]; then
    echo "The Xcode project is missing. Generate it with:" >&2
    echo "  python3 scripts/generate-xcodeproj.py ." >&2
    exit 1
fi

# The target lists its sources one by one, so a Swift file added since the last
# generation would compile under `swift build` and be absent from the app. Regenerating
# is cheap and the identifiers are derived from the paths, so an unchanged tree produces
# an unchanged project file.
python3 "$script_dir/generate-xcodeproj.py" "$project_root"

# The signing team comes from the Apple Development certificate on this Mac, not from
# the project file: that file is tracked, and the team identifies the owner's account.
team=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
    | awk -F' = ' '/organizationalUnitName/ {print $2; exit}')
if [[ -z "$team" ]]; then
    echo "No Apple Development certificate is installed, so the app cannot keep a stable identity." >&2
    exit 1
fi

xcodebuild \
    -project "$project" \
    -scheme VoiceFlowMac \
    -configuration Release \
    -derivedDataPath "$derived" \
    DEVELOPMENT_TEAM="$team" \
    build

built="$derived/Build/Products/Release/${app_dir:t}"
if [[ ! -d "$built" ]]; then
    echo "The build reported success but produced no app at $built." >&2
    exit 1
fi

# Verified before installation, not after: a bundle that fails here must not replace the
# one the speaker is using. macOS binds Input Monitoring to the code identity, so an app
# that arrives unsigned or ad-hoc loses the global Fn/Globe trigger silently.
codesign --verify --deep --strict "$built"

# App Intents are the reason this build exists. If the metadata is missing the build
# succeeded and the product is still the lesser one, so it is refused here rather than
# discovered when Siri does not answer.
if [[ ! -d "$built/Contents/Resources/Metadata.appintents" ]]; then
    echo "The build carries no App Intents metadata; refusing to install it." >&2
    exit 1
fi

rm -rf "$app_dir"
mkdir -p "${app_dir:h}"
cp -R "$built" "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
