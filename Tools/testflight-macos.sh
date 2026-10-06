#!/bin/bash
# macOS archive/export only. Credentials and distribution logs stay outside Git.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
: "${STAGEDISC_TEAM_ID:?Set the Apple Developer signing team in your local environment}"
build="${1:-3}"
[[ "$build" =~ ^[0-9]+$ ]] || { echo 'Build number must be numeric.' >&2; exit 2; }
output="${STAGEDISC_RELEASE_DIR:-$root/build/testflight-$build}"
mkdir -p "$output"
auth=()
if [[ -n "${ASC_ENV_FILE:-}" ]]; then
    set -a
    source "$ASC_ENV_FILE"
    set +a
    : "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_PATH:?}"
    [[ -f "$ASC_KEY_PATH" ]] || { echo 'Private key file missing.' >&2; exit 1; }
    auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
xcodebuild -project "$root/StageDisc.xcodeproj" -scheme StageDisc -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$output/StageDisc.xcarchive" \
  -derivedDataPath "$output/DerivedData" -allowProvisioningUpdates "${auth[@]}" \
  DEVELOPMENT_TEAM="$STAGEDISC_TEAM_ID" CURRENT_PROJECT_VERSION="$build" archive \
  >"$output/archive.log" 2>&1
app="$output/StageDisc.xcarchive/Products/Applications/StageDisc.app"
codesign --verify --deep --strict "$app"
: "${STAGEDISC_SYMBOLS_DIR:?Set the folder containing all four matching helper dSYMs}"
python3 "$root/Tools/verify-helper-symbols.py" "$app/Contents/Resources/bin" "$STAGEDISC_SYMBOLS_DIR"
for name in ffmpeg ffprobe tsMuxeR stagedisc-udf; do
    ditto "$STAGEDISC_SYMBOLS_DIR/$name.dSYM" "$output/StageDisc.xcarchive/dSYMs/$name.dSYM"
done
python3 - "$output/ExportOptions.plist" <<'PY'
import os, plistlib,sys
options={'method':'app-store-connect','destination':'upload','signingStyle':'automatic',
 'teamID':os.environ['STAGEDISC_TEAM_ID'],'manageAppVersionAndBuildNumber':False,
 'testFlightInternalTestingOnly':False,'uploadSymbols':True}
with open(sys.argv[1],'wb') as f: plistlib.dump(options,f)
PY
xcodebuild -exportArchive -archivePath "$output/StageDisc.xcarchive" \
  -exportOptionsPlist "$output/ExportOptions.plist" -exportPath "$output/export" \
  -allowProvisioningUpdates "${auth[@]}" >"$output/upload.log" 2>&1
echo 'Apple upload command succeeded. Verify the build and processing status in App Store Connect.'
