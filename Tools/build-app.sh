#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="${STAGEDISC_BUILD_DIR:-$root/.build-local}"
app="${1:-$(dirname "$root")/StageDisc.app}"
mkdir -p "$scratch"
export CLANG_MODULE_CACHE_PATH="$scratch/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$scratch/module-cache"
swift build --package-path "$root" --scratch-path "$scratch/swift" --cache-path "$scratch/cache" --disable-sandbox -c release
binary_dir="$(swift build --package-path "$root" --scratch-path "$scratch/swift" --cache-path "$scratch/cache" --disable-sandbox -c release --show-bin-path)"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/StageDisc" "$app/Contents/MacOS/StageDisc"
cp -R "$root/Resources/" "$app/Contents/Resources/"
cp "$root/Tools/Info.plist" "$app/Contents/Info.plist"
cp "$root/LICENSE" "$root/THIRD_PARTY.md" "$app/Contents/Resources/"
codesign --force --deep --sign - "$app"
printf '%s\n' "Built $app"
