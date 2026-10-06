#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="${STAGEDISC_DISC_BUILD_DIR:-$root/.build-disc}"
symbols="${STAGEDISC_SYMBOLS_DIR:-$scratch/symbols}"
mkdir -p "$symbols" "$root/Resources/bin"
cmake -S "$root/ThirdParty/tsMuxer" -B "$scratch/tsmuxer" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DTSMUXER_GUI=OFF
cmake --build "$scratch/tsmuxer" --parallel "$(sysctl -n hw.logicalcpu)"
cmake -S "$root/Tools" -B "$scratch/udf" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$scratch/udf" --parallel "$(sysctl -n hw.logicalcpu)"
cp "$scratch/tsmuxer/tsMuxer/tsMuxeR" "$root/Resources/bin/"
cp "$scratch/udf/stagedisc-udf" "$root/Resources/bin/"
for name in tsMuxeR stagedisc-udf; do
    xcrun dsymutil "$root/Resources/bin/$name" -o "$symbols/$name.dSYM"
    strip -S "$root/Resources/bin/$name"
done
echo 'Built disc tools and matching dSYMs with a macOS 14 deployment target.'
