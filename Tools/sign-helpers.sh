#!/bin/bash
set -euo pipefail
app="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
tools="$app/Contents/Resources/bin"
if [[ "${STAGEDISC_DISTRIBUTION:-local}" == "app-store" ]]; then
    for name in ffmpeg ffprobe tsMuxeR stagedisc-udf; do
        [[ -x "$tools/$name" ]] || { echo "error: Missing bundled $name. Build media tools before TestFlight archiving."; exit 1; }
    done
fi
[[ "${CODE_SIGNING_ALLOWED:-YES}" == "YES" ]] || exit 0
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
for name in ffmpeg ffprobe tsMuxeR stagedisc-udf; do
    [[ -f "$tools/$name" ]] || continue
    args=(--force --sign "$identity" --identifier "${PRODUCT_BUNDLE_IDENTIFIER}.tool.${name}")
    if [[ "${STAGEDISC_DISTRIBUTION:-local}" == "app-store" ]]; then args+=(--options runtime --entitlements "$SRCROOT/Tools/Helpers.entitlements"); fi
    /usr/bin/codesign "${args[@]}" "$tools/$name"
done
