#!/usr/bin/env python3
"""Generate `macos/VoiceFlow.xcodeproj`, the build that carries App Intents metadata.

Run it from the project root:  `python3 scripts/generate-xcodeproj.py .`

Why this project exists at all. App Intents are what Siri, Spotlight and Shortcuts read,
and the metadata they read is produced by `appintentsmetadataprocessor`, an Xcode build
phase. Verified twice on 2026-09-18: neither `swift build` nor `xcodebuild` on the package
produces it, because a SwiftPM executable is not an app target. With this project the
bundle carries `Contents/Resources/Metadata.appintents`, and it names `PingVoiceFlowIntent`.

Why a generator rather than a project file edited by hand. The target lists its source
files one by one, so a new `.swift` file under `Sources/VoiceFlowMac/` does not reach the
app until this runs again. A generator makes that a command instead of a merge conflict,
and the identifiers are derived from the file paths, so regenerating produces the same
file rather than a diff of random hex.

What it deliberately does not do. It adds nothing: `scripts/build-macos-app.sh` and
`swift build` keep working exactly as before, and this project compiles the same sources
rather than a copy of them. The app target links `VoiceFlowMacCore` as the package's
library product, which is the boundary `Package.swift` already declares.
"""

import hashlib
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
MACOS = ROOT / "macos"
PROJECT = MACOS / "VoiceFlow.xcodeproj"

APP_NAME = "sanblueᵈᵒᵗ VoiceFlow"
BUNDLE_ID = "dot.sanblue.voiceflow"


def uid(*parts: str) -> str:
    """A stable 24-hex-character identifier, so regenerating gives the same file."""
    digest = hashlib.sha256("::".join(parts).encode("utf-8")).hexdigest()
    return digest[:24].upper()


def sources(directory: Path) -> list[Path]:
    return sorted(p for p in directory.rglob("*.swift"))


app_files = sources(MACOS / "Sources" / "VoiceFlowMac")
all_files = app_files

file_refs: list[str] = []
build_files: list[str] = []
group_children: list[str] = []
sources_phase: list[str] = []

for path in all_files:
    relative = path.relative_to(MACOS).as_posix()
    ref = uid("fileRef", relative)
    build = uid("buildFile", relative)
    file_refs.append(
        f'\t\t{ref} /* {path.name} */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = sourcecode.swift; name = "{path.name}"; '
        f'path = "{relative}"; sourceTree = "<group>"; }};'
    )
    build_files.append(
        f'\t\t{build} /* {path.name} in Sources */ = {{isa = PBXBuildFile; '
        f'fileRef = {ref} /* {path.name} */; }};'
    )
    group_children.append(f"\t\t\t\t{ref} /* {path.name} */,")
    sources_phase.append(f"\t\t\t\t{build} /* {path.name} in Sources */,")

# Resources copied into the bundle, matching what the shell script installs.
resource_names = ["AppIcon.icns", "voiceflow-badge-round.png", "Fonts"]
resource_refs: list[str] = []
resource_build: list[str] = []
resource_children: list[str] = []
resource_phase: list[str] = []
for name in resource_names:
    source = MACOS / "Resources" / name
    if not source.exists():
        continue
    relative = f"Resources/{name}"
    ref = uid("fileRef", relative)
    build = uid("buildFile", relative)
    kind = "folder" if source.is_dir() else "file"
    resource_refs.append(
        f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {kind}; '
        f'name = "{name}"; path = "{relative}"; sourceTree = "<group>"; }};'
    )
    resource_build.append(
        f'\t\t{build} /* {name} in Resources */ = {{isa = PBXBuildFile; '
        f'fileRef = {ref} /* {name} */; }};'
    )
    resource_children.append(f"\t\t\t\t{ref} /* {name} */,")
    resource_phase.append(f"\t\t\t\t{build} /* {name} in Resources */,")

# What the app has to carry besides its own binary: the Python engine it runs, and the
# helper that reaches Apple's on-device model. `scripts/build-macos-app.sh` installs both
# the same way, and a bundle without them launches and then fails on the first dictation.
ENGINE_PHASE = """set -euo pipefail
root="$PROJECT_DIR/.."
app="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH"
mkdir -p "$app/Resources/python/src"
/usr/bin/rsync -a --delete --exclude=__pycache__ --exclude='*.py[co]' "$root/src/" "$app/Resources/python/src/"
swift build --package-path "$PROJECT_DIR" -c release --product VoiceFlowAppleCleaner >/dev/null
bin=$(swift build --package-path "$PROJECT_DIR" -c release --show-bin-path)
install -m 755 "$bin/VoiceFlowAppleCleaner" "$app/MacOS/voiceflow-apple-cleaner"
# Parakeet's helper is its own package, so FluidAudio never enters the app's build.
swift build --package-path "$PROJECT_DIR/ParakeetHelper" -c release --product VoiceFlowParakeet >/dev/null
parakeet_bin=$(swift build --package-path "$PROJECT_DIR/ParakeetHelper" -c release --show-bin-path)
install -m 755 "$parakeet_bin/VoiceFlowParakeet" "$app/MacOS/voiceflow-parakeet"
# Xcode signs before this phase runs, so everything embedded here arrives after the
# seal was computed and `codesign --verify` reports the files as added. Signing the
# helpers first and the bundle last puts the seal back over what is actually there.
codesign --force --options runtime --timestamp=none \
    --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$app/MacOS/voiceflow-apple-cleaner"
codesign --force --options runtime --timestamp=none \
    --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$app/MacOS/voiceflow-parakeet"
codesign --force --options runtime --timestamp=none \
    --entitlements "$PROJECT_DIR/Resources/VoiceFlowMac.entitlements" \
    --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$BUILT_PRODUCTS_DIR/$WRAPPER_NAME"
codesign --verify --deep --strict "$BUILT_PRODUCTS_DIR/$WRAPPER_NAME"
"""


def pbx_string(value: str) -> str:
    """Escape a shell script for the quoted pbxproj string it lives inside."""
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )


engine_phase_script = pbx_string(ENGINE_PHASE)

ids = {name: uid("object", name) for name in (
    "project", "target", "productRef", "mainGroup", "sourcesGroup", "resourcesGroup",
    "productsGroup", "sourcesPhase", "resourcesPhase", "frameworksPhase",
    "buildConfigList", "targetConfigList", "projectDebug", "projectRelease",
    "targetDebug", "targetRelease", "infoPlistRef",
    "packageRef", "productDep", "productBuildFile", "enginePhase",
)}

# One shared setting block, so Debug and Release cannot drift apart on the things that
# decide whether the app runs at all: its identity, its entitlement, and the deployment
# target the on-device model needs. The team is not written here: the project file is
# tracked and the team identifies the owner's Apple account, so `build-macos-app.sh`
# reads it from the installed certificate and passes it to `xcodebuild`.
target_settings = f'''\t\t\t\tCODE_SIGN_ENTITLEMENTS = "Resources/VoiceFlowMac.entitlements";
\t\t\t\tCODE_SIGN_IDENTITY = "Apple Development";
\t\t\t\tCODE_SIGN_STYLE = Manual;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = "Resources/Info.plist";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{BUNDLE_ID}";
\t\t\t\tPRODUCT_NAME = "{APP_NAME}";
\t\t\t\t// The bundle is named for the brand and the binary is not. `Info.plist`
\t\t\t\t// declares CFBundleExecutable = VoiceFlowMac, and codesign refuses a bundle
\t\t\t\t// whose declared main executable is not the file that is there.
\t\t\t\tEXECUTABLE_NAME = VoiceFlowMac;
\t\t\t\tSWIFT_VERSION = 5.0;'''

pbxproj = f'''// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files + resource_build)}
\t\t{ids["productBuildFile"]} /* VoiceFlowMacCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {ids["productDep"]} /* VoiceFlowMacCore */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs + resource_refs)}
\t\t{ids["infoPlistRef"]} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; name = "Info.plist"; path = "Resources/Info.plist"; sourceTree = "<group>"; }};
\t\t{ids["productRef"]} /* {APP_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "{APP_NAME}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{ids["frameworksPhase"]} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{ids["productBuildFile"]} /* VoiceFlowMacCore in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{ids["mainGroup"]} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ids["sourcesGroup"]} /* Sources */,
\t\t\t\t{ids["resourcesGroup"]} /* Resources */,
\t\t\t\t{ids["productsGroup"]} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{ids["sourcesGroup"]} /* Sources */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(group_children)}
\t\t\t);
\t\t\tname = Sources;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{ids["resourcesGroup"]} /* Resources */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ids["infoPlistRef"]} /* Info.plist */,
{chr(10).join(resource_children)}
\t\t\t);
\t\t\tname = Resources;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{ids["productsGroup"]} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ids["productRef"]} /* {APP_NAME}.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{ids["target"]} /* VoiceFlowMac */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {ids["targetConfigList"]} /* Build configuration list for PBXNativeTarget "VoiceFlowMac" */;
\t\t\tbuildPhases = (
\t\t\t\t{ids["sourcesPhase"]} /* Sources */,
\t\t\t\t{ids["frameworksPhase"]} /* Frameworks */,
\t\t\t\t{ids["resourcesPhase"]} /* Resources */,
\t\t\t\t{ids["enginePhase"]} /* Embed the engine */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = VoiceFlowMac;
\t\t\tpackageProductDependencies = (
\t\t\t\t{ids["productDep"]} /* VoiceFlowMacCore */,
\t\t\t);
\t\t\tproductName = VoiceFlowMac;
\t\t\tproductReference = {ids["productRef"]} /* {APP_NAME}.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{ids["project"]} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2700;
\t\t\t\tLastUpgradeCheck = 2700;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{ids["target"]} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {ids["buildConfigList"]} /* Build configuration list for PBXProject "VoiceFlow" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {ids["mainGroup"]};
\t\t\tpackageReferences = (
\t\t\t\t{ids["packageRef"]} /* XCLocalSwiftPackageReference "." */,
\t\t\t);
\t\t\tproductRefGroup = {ids["productsGroup"]} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{ids["target"]} /* VoiceFlowMac */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXShellScriptBuildPhase section */
\t\t{ids["enginePhase"]} /* Embed the engine */ = {{
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\talwaysOutOfDate = 1;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\tinputPaths = (
\t\t\t);
\t\t\tname = "Embed the engine";
\t\t\toutputPaths = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = "{engine_phase_script}";
\t\t}};
/* End PBXShellScriptBuildPhase section */

/* Begin PBXResourcesBuildPhase section */
\t\t{ids["resourcesPhase"]} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(resource_phase)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{ids["sourcesPhase"]} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(sources_phase)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{ids["projectDebug"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ids["projectRelease"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{ids["targetDebug"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{target_settings}
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ids["targetRelease"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{target_settings}
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{ids["buildConfigList"]} /* Build configuration list for PBXProject "VoiceFlow" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ids["projectDebug"]} /* Debug */,
\t\t\t\t{ids["projectRelease"]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{ids["targetConfigList"]} /* Build configuration list for PBXNativeTarget "VoiceFlowMac" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ids["targetDebug"]} /* Debug */,
\t\t\t\t{ids["targetRelease"]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
\t\t{ids["packageRef"]} /* XCLocalSwiftPackageReference "." */ = {{
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = .;
\t\t}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{ids["productDep"]} /* VoiceFlowMacCore */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tproductName = VoiceFlowMacCore;
\t\t}};
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {ids["project"]} /* Project object */;
}}
'''

PROJECT.mkdir(parents=True, exist_ok=True)
(PROJECT / "project.pbxproj").write_text(pbxproj, encoding="utf-8")

shared = PROJECT / "xcshareddata" / "xcschemes"
shared.mkdir(parents=True, exist_ok=True)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2700" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ids["target"]}"
               BuildableName = "{APP_NAME}.app"
               BlueprintName = "VoiceFlowMac"
               ReferencedContainer = "container:VoiceFlow.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ids["target"]}"
            BuildableName = "{APP_NAME}.app"
            BlueprintName = "VoiceFlowMac"
            ReferencedContainer = "container:VoiceFlow.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
(shared / "VoiceFlowMac.xcscheme").write_text(scheme, encoding="utf-8")

print(f"{len(all_files)} sources, {len(resource_refs)} resource entries")
print(f"written: {PROJECT}")
